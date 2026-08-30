package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	defaultListenAddress = ":8551"
	defaultMaxBodyBytes  = int64(32 * 1024 * 1024)
	defaultMirrorWorkers = 8
	defaultTimeout       = 15 * time.Second
	probeMaxBodyBytes    = int64(64 * 1024)
	probeTimeout         = 2 * time.Second
)

type responseMeta struct {
	httpStatus   int
	engineStatus string
	err          error
}

type proxyCounters struct {
	primaryRequests  atomic.Uint64
	primaryErrors    atomic.Uint64
	mirrorStarted    atomic.Uint64
	mirrorSucceeded  atomic.Uint64
	mirrorErrors     atomic.Uint64
	mirrorDropped    atomic.Uint64
	statusMismatches atomic.Uint64
}

type engineProxy struct {
	primaryURL      *url.URL
	secondaryURL    *url.URL
	primaryClient   *http.Client
	secondaryClient *http.Client
	maxBodyBytes    int64
	mirrorSlots     chan struct{}
	counters        proxyCounters
	mirrors         sync.WaitGroup
}

func parseTarget(raw string) (*url.URL, error) {
	target, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if target.Scheme != "http" || target.Host == "" || target.User != nil {
		return nil, fmt.Errorf("target must be an http URL without userinfo")
	}
	if target.RawQuery != "" || target.Fragment != "" {
		return nil, fmt.Errorf("target must not contain a query or fragment")
	}
	if target.Path != "" && target.Path != "/" {
		return nil, fmt.Errorf("target must not contain a path")
	}
	return target, nil
}

func upstreamClient() *http.Client {
	return &http.Client{
		Timeout: defaultTimeout,
		CheckRedirect: func(request *http.Request, via []*http.Request) error {
			return errors.New("upstream redirects are forbidden")
		},
	}
}

func probeLocalURL(raw string, output io.Writer) error {
	target, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if target.Scheme != "http" || target.Hostname() != "127.0.0.1" ||
		target.User != nil || target.RawQuery != "" || target.Fragment != "" {
		return errors.New("probe target must be a plain loopback HTTP URL")
	}
	if target.Path != "/healthz" && target.Path != "/metrics" {
		return errors.New("probe path must be /healthz or /metrics")
	}
	client := upstreamClient()
	client.Timeout = probeTimeout
	response, err := client.Get(target.String())
	if err != nil {
		return err
	}
	defer response.Body.Close()
	expectedStatus := http.StatusOK
	if target.Path == "/healthz" {
		expectedStatus = http.StatusNoContent
	}
	if response.StatusCode != expectedStatus {
		return fmt.Errorf("probe returned HTTP %d, expected %d", response.StatusCode, expectedStatus)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, probeMaxBodyBytes+1))
	if err != nil {
		return err
	}
	if int64(len(body)) > probeMaxBodyBytes {
		return errors.New("probe response exceeds configured bound")
	}
	if target.Path == "/metrics" {
		_, err = output.Write(body)
	}
	return err
}

func newEngineProxy(primary, secondary *url.URL, maxBodyBytes int64, mirrorWorkers int) *engineProxy {
	return &engineProxy{
		primaryURL:      primary,
		secondaryURL:    secondary,
		primaryClient:   upstreamClient(),
		secondaryClient: upstreamClient(),
		maxBodyBytes:    maxBodyBytes,
		mirrorSlots:     make(chan struct{}, mirrorWorkers),
	}
}

func copyRequestHeaders(destination, source http.Header) {
	for name, values := range source {
		switch strings.ToLower(name) {
		case "connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade":
			continue
		}
		for _, value := range values {
			destination.Add(name, value)
		}
	}
}

func targetURL(base *url.URL, request *http.Request) string {
	target := *base
	target.Path = request.URL.Path
	target.RawPath = request.URL.RawPath
	target.RawQuery = request.URL.RawQuery
	return target.String()
}

func requestMethod(body []byte) string {
	var envelope struct {
		Method string `json:"method"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil || envelope.Method == "" {
		return "unknown"
	}
	for _, character := range envelope.Method {
		if !((character >= 'a' && character <= 'z') ||
			(character >= 'A' && character <= 'Z') ||
			(character >= '0' && character <= '9') || character == '_') {
			return "unknown"
		}
	}
	return envelope.Method
}

func responseEngineStatus(body []byte) string {
	var envelope struct {
		Result struct {
			Status string `json:"status"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return ""
	}
	switch envelope.Result.Status {
	case "VALID", "INVALID", "SYNCING", "ACCEPTED", "INVALID_BLOCK_HASH":
		return envelope.Result.Status
	default:
		return ""
	}
}

func (proxy *engineProxy) callTarget(
	ctx context.Context,
	client *http.Client,
	target *url.URL,
	incoming *http.Request,
	body []byte,
) (int, http.Header, []byte, error) {
	request, err := http.NewRequestWithContext(
		ctx, incoming.Method, targetURL(target, incoming), bytes.NewReader(body),
	)
	if err != nil {
		return 0, nil, nil, err
	}
	copyRequestHeaders(request.Header, incoming.Header)
	request.Host = ""
	response, err := client.Do(request)
	if err != nil {
		return 0, nil, nil, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, proxy.maxBodyBytes+1))
	if err != nil {
		return 0, nil, nil, err
	}
	if int64(len(responseBody)) > proxy.maxBodyBytes {
		return 0, nil, nil, errors.New("upstream response exceeds configured bound")
	}
	return response.StatusCode, response.Header.Clone(), responseBody, nil
}

func (proxy *engineProxy) mirror(
	incoming *http.Request,
	body []byte,
	method string,
	primary <-chan responseMeta,
) {
	defer proxy.mirrors.Done()
	defer func() { <-proxy.mirrorSlots }()
	proxy.counters.mirrorStarted.Add(1)
	status, _, responseBody, err := proxy.callTarget(
		context.Background(), proxy.secondaryClient, proxy.secondaryURL, incoming, body,
	)
	secondary := responseMeta{
		httpStatus:   status,
		engineStatus: responseEngineStatus(responseBody),
		err:          err,
	}
	primaryMeta := <-primary
	if secondary.err != nil {
		proxy.counters.mirrorErrors.Add(1)
		log.Printf("shadow_proxy method=%s secondary=error", method)
		return
	}
	proxy.counters.mirrorSucceeded.Add(1)
	if primaryMeta.err == nil && primaryMeta.engineStatus != "" && secondary.engineStatus != "" &&
		primaryMeta.engineStatus != secondary.engineStatus {
		proxy.counters.statusMismatches.Add(1)
		log.Printf(
			"shadow_proxy method=%s primary_status=%s secondary_status=%s mismatch=true",
			method, primaryMeta.engineStatus, secondary.engineStatus,
		)
		return
	}
	log.Printf("shadow_proxy method=%s secondary_http=%d mirrored=true", method, secondary.httpStatus)
}

func (proxy *engineProxy) metrics(response http.ResponseWriter) {
	response.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(response, "shadow_primary_requests_total %d\n", proxy.counters.primaryRequests.Load())
	fmt.Fprintf(response, "shadow_primary_errors_total %d\n", proxy.counters.primaryErrors.Load())
	fmt.Fprintf(response, "shadow_mirror_started_total %d\n", proxy.counters.mirrorStarted.Load())
	fmt.Fprintf(response, "shadow_mirror_succeeded_total %d\n", proxy.counters.mirrorSucceeded.Load())
	fmt.Fprintf(response, "shadow_mirror_errors_total %d\n", proxy.counters.mirrorErrors.Load())
	fmt.Fprintf(response, "shadow_mirror_dropped_total %d\n", proxy.counters.mirrorDropped.Load())
	fmt.Fprintf(response, "shadow_status_mismatches_total %d\n", proxy.counters.statusMismatches.Load())
}

func (proxy *engineProxy) ServeHTTP(response http.ResponseWriter, request *http.Request) {
	switch request.URL.Path {
	case "/healthz":
		response.WriteHeader(http.StatusNoContent)
		return
	case "/metrics":
		proxy.metrics(response)
		return
	}

	proxy.counters.primaryRequests.Add(1)
	request.Body = http.MaxBytesReader(response, request.Body, proxy.maxBodyBytes)
	body, err := io.ReadAll(request.Body)
	if err != nil {
		http.Error(response, "request body exceeds configured bound", http.StatusRequestEntityTooLarge)
		return
	}
	method := requestMethod(body)

	var primaryMeta chan responseMeta
	select {
	case proxy.mirrorSlots <- struct{}{}:
		primaryMeta = make(chan responseMeta, 1)
		proxy.mirrors.Add(1)
		go proxy.mirror(request.Clone(context.Background()), body, method, primaryMeta)
	default:
		proxy.counters.mirrorDropped.Add(1)
		log.Printf("shadow_proxy method=%s secondary=dropped", method)
	}

	status, headers, responseBody, primaryErr := proxy.callTarget(
		request.Context(), proxy.primaryClient, proxy.primaryURL, request, body,
	)
	meta := responseMeta{
		httpStatus:   status,
		engineStatus: responseEngineStatus(responseBody),
		err:          primaryErr,
	}
	if primaryMeta != nil {
		primaryMeta <- meta
		close(primaryMeta)
	}
	if primaryErr != nil {
		proxy.counters.primaryErrors.Add(1)
		http.Error(response, "primary execution endpoint unavailable", http.StatusBadGateway)
		return
	}
	if contentType := headers.Get("Content-Type"); contentType != "" {
		response.Header().Set("Content-Type", contentType)
	}
	response.WriteHeader(status)
	_, _ = response.Write(responseBody)
}

func envInt64(name string, fallback int64) (int64, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return value, nil
}

func envInt(name string, fallback int) (int, error) {
	value, err := envInt64(name, int64(fallback))
	if err != nil {
		return 0, err
	}
	if value > 64 {
		return 0, fmt.Errorf("%s must not exceed 64", name)
	}
	return int(value), nil
}

func main() {
	probePath := flag.String("probe-path", "", "probe the local /healthz or /metrics endpoint and exit")
	flag.Parse()
	if *probePath != "" {
		if *probePath != "/healthz" && *probePath != "/metrics" {
			log.Fatal("invalid probe path")
		}
		if err := probeLocalURL("http://127.0.0.1:8551"+*probePath, os.Stdout); err != nil {
			log.Fatal("local probe failed: ", err)
		}
		return
	}
	listen := os.Getenv("SHADOW_PROXY_LISTEN")
	if listen == "" {
		listen = defaultListenAddress
	}
	primary, err := parseTarget(os.Getenv("SHADOW_PROXY_PRIMARY_URL"))
	if err != nil {
		log.Fatal("invalid SHADOW_PROXY_PRIMARY_URL: ", err)
	}
	secondary, err := parseTarget(os.Getenv("SHADOW_PROXY_SECONDARY_URL"))
	if err != nil {
		log.Fatal("invalid SHADOW_PROXY_SECONDARY_URL: ", err)
	}
	maxBodyBytes, err := envInt64("SHADOW_PROXY_MAX_BODY_BYTES", defaultMaxBodyBytes)
	if err != nil {
		log.Fatal(err)
	}
	mirrorWorkers, err := envInt("SHADOW_PROXY_MIRROR_WORKERS", defaultMirrorWorkers)
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Addr:              listen,
		Handler:           newEngineProxy(primary, secondary, maxBodyBytes, mirrorWorkers),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("shadow_proxy listen=%s mirror_workers=%d max_body_bytes=%d", listen, mirrorWorkers, maxBodyBytes)
	log.Fatal(server.ListenAndServe())
}
