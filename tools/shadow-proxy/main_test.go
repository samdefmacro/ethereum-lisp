package main

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func mustURL(t *testing.T, raw string) *url.URL {
	t.Helper()
	parsed, err := parseTarget(raw)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func newTestProxy(t *testing.T, primary, secondary *httptest.Server, maxBody int64) *engineProxy {
	t.Helper()
	proxy := newEngineProxy(mustURL(t, primary.URL), mustURL(t, secondary.URL), maxBody, 2)
	proxy.primaryClient = primary.Client()
	proxy.secondaryClient = secondary.Client()
	return proxy
}

func TestReturnsPrimaryWithoutWaitingForSecondary(t *testing.T) {
	release := make(chan struct{})
	primary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(response, `{"jsonrpc":"2.0","id":1,"result":{"status":"VALID"}}`)
	}))
	defer primary.Close()
	secondary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		<-release
		_, _ = io.WriteString(response, `{"jsonrpc":"2.0","id":1,"result":{"status":"VALID"}}`)
	}))
	defer secondary.Close()
	proxy := newTestProxy(t, primary, secondary, 4096)

	request := httptest.NewRequest(http.MethodPost, "http://proxy/", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"engine_newPayloadV4","params":[]}`))
	response := httptest.NewRecorder()
	started := time.Now()
	proxy.ServeHTTP(response, request)
	if elapsed := time.Since(started); elapsed > 250*time.Millisecond {
		t.Fatalf("primary response waited for shadow: %s", elapsed)
	}
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"VALID"`) {
		t.Fatalf("unexpected primary response: %d %s", response.Code, response.Body.String())
	}
	close(release)
	proxy.mirrors.Wait()
	if proxy.counters.mirrorSucceeded.Load() != 1 {
		t.Fatalf("mirror did not complete")
	}
}

func TestForwardsAuthorizationAndBodyToBothTargets(t *testing.T) {
	type observed struct {
		authorization string
		body          []byte
	}
	observations := make(chan observed, 2)
	handler := http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, _ := io.ReadAll(request.Body)
		observations <- observed{request.Header.Get("Authorization"), body}
		response.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(response, `{"jsonrpc":"2.0","id":1,"result":{"status":"SYNCING"}}`)
	})
	primary := httptest.NewServer(handler)
	defer primary.Close()
	secondary := httptest.NewServer(handler)
	defer secondary.Close()
	proxy := newTestProxy(t, primary, secondary, 4096)
	payload := []byte(`{"jsonrpc":"2.0","id":1,"method":"engine_forkchoiceUpdatedV3","params":[]}`)
	request := httptest.NewRequest(http.MethodPost, "http://proxy/", bytes.NewReader(payload))
	request.Header.Set("Authorization", "Bearer exact-jwt")
	response := httptest.NewRecorder()
	proxy.ServeHTTP(response, request)
	proxy.mirrors.Wait()
	for index := 0; index < 2; index++ {
		got := <-observations
		if got.authorization != "Bearer exact-jwt" || !bytes.Equal(got.body, payload) {
			t.Fatalf("request was not mirrored exactly: %#v", got)
		}
	}
}

func TestRejectsOversizedBodyBeforeUpstream(t *testing.T) {
	calls := make(chan struct{}, 2)
	handler := http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		calls <- struct{}{}
	})
	primary := httptest.NewServer(handler)
	defer primary.Close()
	secondary := httptest.NewServer(handler)
	defer secondary.Close()
	proxy := newTestProxy(t, primary, secondary, 8)
	request := httptest.NewRequest(http.MethodPost, "http://proxy/", strings.NewReader("123456789"))
	response := httptest.NewRecorder()
	proxy.ServeHTTP(response, request)
	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized request returned %d", response.Code)
	}
	select {
	case <-calls:
		t.Fatal("oversized request reached an upstream")
	default:
	}
}

func TestHealthAndMetricsAreLocal(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		t.Fatal("local endpoint reached upstream")
	}))
	defer upstream.Close()
	proxy := newTestProxy(t, upstream, upstream, 4096)
	for _, test := range []struct {
		path   string
		status int
	}{
		{"/healthz", http.StatusNoContent},
		{"/metrics", http.StatusOK},
	} {
		response := httptest.NewRecorder()
		proxy.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "http://proxy"+test.path, nil))
		if response.Code != test.status {
			t.Fatalf("%s returned %d", test.path, response.Code)
		}
	}
}

func TestPrimaryRedirectIsNotFollowed(t *testing.T) {
	redirectTargetCalled := make(chan struct{}, 1)
	redirectTarget := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		redirectTargetCalled <- struct{}{}
	}))
	defer redirectTarget.Close()
	primary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		http.Redirect(response, request, redirectTarget.URL, http.StatusTemporaryRedirect)
	}))
	defer primary.Close()
	secondary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		_, _ = io.WriteString(response, `{"jsonrpc":"2.0","id":1,"result":{"status":"SYNCING"}}`)
	}))
	defer secondary.Close()
	proxy := newTestProxy(t, primary, secondary, 4096)
	proxy.primaryClient = upstreamClient()
	request := httptest.NewRequest(http.MethodPost, "http://proxy/", strings.NewReader(`{"method":"engine_newPayloadV4"}`))
	response := httptest.NewRecorder()
	proxy.ServeHTTP(response, request)
	proxy.mirrors.Wait()
	if response.Code != http.StatusBadGateway {
		t.Fatalf("redirect returned %d", response.Code)
	}
	select {
	case <-redirectTargetCalled:
		t.Fatal("proxy followed an upstream redirect")
	default:
	}
}

func TestTargetValidation(t *testing.T) {
	for _, raw := range []string{"", "https://example.invalid", "http://user@example.invalid", "http://example.invalid?x=1", "http://example.invalid/rpc"} {
		if _, err := parseTarget(raw); err == nil {
			t.Fatalf("accepted unsafe target %q", raw)
		}
	}
}

func TestCountsRejectedUpstreamResponsesAsErrors(t *testing.T) {
	primary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(response, `{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"internal"}}`)
	}))
	defer primary.Close()
	secondary := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		http.Error(response, "unauthorized", http.StatusUnauthorized)
	}))
	defer secondary.Close()
	proxy := newTestProxy(t, primary, secondary, 4096)
	request := httptest.NewRequest(http.MethodPost, "http://proxy/", strings.NewReader(`{"method":"engine_forkchoiceUpdatedV3"}`))
	response := httptest.NewRecorder()
	proxy.ServeHTTP(response, request)
	proxy.mirrors.Wait()
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"error"`) {
		t.Fatalf("primary JSON-RPC error was not returned exactly: %d %s", response.Code, response.Body.String())
	}
	if proxy.counters.primaryErrors.Load() != 1 {
		t.Fatal("primary JSON-RPC error was not counted")
	}
	if proxy.counters.mirrorErrors.Load() != 1 || proxy.counters.mirrorSucceeded.Load() != 0 {
		t.Fatal("secondary HTTP rejection was counted as a successful mirror")
	}
}

func TestLocalProbeIsBoundedToLoopbackEndpoints(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/healthz":
			response.WriteHeader(http.StatusNoContent)
		case "/metrics":
			_, _ = io.WriteString(response, "shadow_primary_requests_total 7\n")
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	var output bytes.Buffer
	if err := probeLocalURL(server.URL+"/healthz", &output); err != nil {
		t.Fatal(err)
	}
	if output.Len() != 0 {
		t.Fatalf("health probe emitted output: %q", output.String())
	}
	if err := probeLocalURL(server.URL+"/metrics", &output); err != nil {
		t.Fatal(err)
	}
	if output.String() != "shadow_primary_requests_total 7\n" {
		t.Fatalf("unexpected metrics output: %q", output.String())
	}
	for _, raw := range []string{
		"https://127.0.0.1:8551/metrics",
		"http://localhost:8551/metrics",
		"http://127.0.0.1:8551/",
		"http://127.0.0.1:8551/metrics?all=true",
	} {
		if err := probeLocalURL(raw, io.Discard); err == nil {
			t.Fatalf("accepted unsafe probe target %q", raw)
		}
	}
}
