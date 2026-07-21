// Command bls12381 is a persistent EIP-2537 BLS12-381 backend.
//
// It reads newline-delimited requests on stdin and writes newline-delimited
// responses on stdout, so a single process serves many precompile calls:
//
//	<operation> <hex-input>\n   ->   ok <hex-output>\n
//	                                 err <message>\n
//
// Passing the request as command-line arguments instead runs a single
// operation and exits, which keeps the tool usable for manual inspection.
//
// The numeric work is delegated to gnark-crypto. This program owns only the
// EIP-2537 encoding, the point validity rules, and the request framing.
package main

import (
	"bufio"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/consensys/gnark-crypto/ecc"
	bls12381 "github.com/consensys/gnark-crypto/ecc/bls12-381"
	"github.com/consensys/gnark-crypto/ecc/bls12-381/fp"
	"github.com/consensys/gnark-crypto/ecc/bls12-381/fr"
)

// Encoded sizes fixed by EIP-2537. A base field element occupies 64 bytes: 16
// zero bytes followed by the 48-byte big-endian integer.
const (
	fpEncodedSize     = 64
	fp2EncodedSize    = 128
	g1EncodedSize     = 128
	g2EncodedSize     = 256
	scalarEncodedSize = 32

	g1MSMPairSize  = g1EncodedSize + scalarEncodedSize // 160
	g2MSMPairSize  = g2EncodedSize + scalarEncodedSize // 288
	pairingSetSize = g1EncodedSize + g2EncodedSize     // 384

	protocolVersion = "ethereum-lisp-bls12381-v1"
)

func decodeFp(in []byte) (fp.Element, error) {
	var element fp.Element
	if len(in) != fpEncodedSize {
		return element, errors.New("invalid field element length")
	}
	for _, b := range in[:fpEncodedSize-fp.Bytes] {
		if b != 0 {
			return element, errors.New("field element has non-zero padding")
		}
	}
	// SetBytesCanonical rejects any encoding that is not strictly below the
	// base field modulus, which EIP-2537 requires.
	if err := element.SetBytesCanonical(in[fpEncodedSize-fp.Bytes:]); err != nil {
		return element, errors.New("field element is not less than the modulus")
	}
	return element, nil
}

func encodeFp(element *fp.Element) []byte {
	out := make([]byte, fpEncodedSize)
	bytes := element.Bytes()
	copy(out[fpEncodedSize-fp.Bytes:], bytes[:])
	return out
}

func decodeG1(in []byte) (bls12381.G1Affine, error) {
	var point bls12381.G1Affine
	if len(in) != g1EncodedSize {
		return point, errors.New("invalid G1 point length")
	}
	x, err := decodeFp(in[:fpEncodedSize])
	if err != nil {
		return point, err
	}
	y, err := decodeFp(in[fpEncodedSize:])
	if err != nil {
		return point, err
	}
	point.X, point.Y = x, y
	// An all-zero encoding is the point at infinity by convention. Every other
	// point must satisfy the curve equation.
	if point.X.IsZero() && point.Y.IsZero() {
		return point, nil
	}
	if !point.IsOnCurve() {
		return point, errors.New("point is not on the G1 curve")
	}
	return point, nil
}

func encodeG1(point *bls12381.G1Affine) []byte {
	out := make([]byte, g1EncodedSize)
	if point.IsInfinity() {
		return out
	}
	copy(out[:fpEncodedSize], encodeFp(&point.X))
	copy(out[fpEncodedSize:], encodeFp(&point.Y))
	return out
}

// decodeFp2 reads an Fp2 element c0 + c1*u encoded as encode(c0) || encode(c1).
func decodeFp2(in []byte) (fp.Element, fp.Element, error) {
	var c0, c1 fp.Element
	if len(in) != fp2EncodedSize {
		return c0, c1, errors.New("invalid extension field element length")
	}
	c0, err := decodeFp(in[:fpEncodedSize])
	if err != nil {
		return c0, c1, err
	}
	c1, err = decodeFp(in[fpEncodedSize:])
	if err != nil {
		return c0, c1, err
	}
	return c0, c1, nil
}

func decodeG2(in []byte) (bls12381.G2Affine, error) {
	var point bls12381.G2Affine
	if len(in) != g2EncodedSize {
		return point, errors.New("invalid G2 point length")
	}
	xc0, xc1, err := decodeFp2(in[:fp2EncodedSize])
	if err != nil {
		return point, err
	}
	yc0, yc1, err := decodeFp2(in[fp2EncodedSize:])
	if err != nil {
		return point, err
	}
	point.X.A0, point.X.A1 = xc0, xc1
	point.Y.A0, point.Y.A1 = yc0, yc1
	if point.X.IsZero() && point.Y.IsZero() {
		return point, nil
	}
	if !point.IsOnCurve() {
		return point, errors.New("point is not on the G2 curve")
	}
	return point, nil
}

func encodeG2(point *bls12381.G2Affine) []byte {
	out := make([]byte, g2EncodedSize)
	if point.IsInfinity() {
		return out
	}
	copy(out[:fpEncodedSize], encodeFp(&point.X.A0))
	copy(out[fpEncodedSize:fp2EncodedSize], encodeFp(&point.X.A1))
	copy(out[fp2EncodedSize:fp2EncodedSize+fpEncodedSize], encodeFp(&point.Y.A0))
	copy(out[fp2EncodedSize+fpEncodedSize:], encodeFp(&point.Y.A1))
	return out
}

// decodeScalar reads a 32-byte big-endian scalar. EIP-2537 does not require
// scalars to be below the subgroup order; reducing is sound because every
// point reaching an MSM has already passed a subgroup check.
func decodeScalar(in []byte) (fr.Element, error) {
	var scalar fr.Element
	if len(in) != scalarEncodedSize {
		return scalar, errors.New("invalid scalar length")
	}
	scalar.SetBytes(in)
	return scalar, nil
}

func g1Add(in []byte) ([]byte, error) {
	if len(in) != 2*g1EncodedSize {
		return nil, errors.New("invalid G1 addition input length")
	}
	a, err := decodeG1(in[:g1EncodedSize])
	if err != nil {
		return nil, err
	}
	b, err := decodeG1(in[g1EncodedSize:])
	if err != nil {
		return nil, err
	}
	// EIP-2537 specifies no subgroup check for the addition precompiles.
	var sum bls12381.G1Affine
	sum.Add(&a, &b)
	return encodeG1(&sum), nil
}

func g2Add(in []byte) ([]byte, error) {
	if len(in) != 2*g2EncodedSize {
		return nil, errors.New("invalid G2 addition input length")
	}
	a, err := decodeG2(in[:g2EncodedSize])
	if err != nil {
		return nil, err
	}
	b, err := decodeG2(in[g2EncodedSize:])
	if err != nil {
		return nil, err
	}
	var sum bls12381.G2Affine
	sum.Add(&a, &b)
	return encodeG2(&sum), nil
}

func g1MSM(in []byte) ([]byte, error) {
	if len(in) == 0 || len(in)%g1MSMPairSize != 0 {
		return nil, errors.New("invalid G1 MSM input length")
	}
	count := len(in) / g1MSMPairSize
	points := make([]bls12381.G1Affine, count)
	scalars := make([]fr.Element, count)
	for i := 0; i < count; i++ {
		offset := i * g1MSMPairSize
		point, err := decodeG1(in[offset : offset+g1EncodedSize])
		if err != nil {
			return nil, err
		}
		if !point.IsInSubGroup() {
			return nil, errors.New("G1 point is not in the correct subgroup")
		}
		scalar, err := decodeScalar(in[offset+g1EncodedSize : offset+g1MSMPairSize])
		if err != nil {
			return nil, err
		}
		points[i], scalars[i] = point, scalar
	}
	var result bls12381.G1Affine
	if _, err := result.MultiExp(points, scalars, ecc.MultiExpConfig{}); err != nil {
		return nil, err
	}
	return encodeG1(&result), nil
}

func g2MSM(in []byte) ([]byte, error) {
	if len(in) == 0 || len(in)%g2MSMPairSize != 0 {
		return nil, errors.New("invalid G2 MSM input length")
	}
	count := len(in) / g2MSMPairSize
	points := make([]bls12381.G2Affine, count)
	scalars := make([]fr.Element, count)
	for i := 0; i < count; i++ {
		offset := i * g2MSMPairSize
		point, err := decodeG2(in[offset : offset+g2EncodedSize])
		if err != nil {
			return nil, err
		}
		if !point.IsInSubGroup() {
			return nil, errors.New("G2 point is not in the correct subgroup")
		}
		scalar, err := decodeScalar(in[offset+g2EncodedSize : offset+g2MSMPairSize])
		if err != nil {
			return nil, err
		}
		points[i], scalars[i] = point, scalar
	}
	var result bls12381.G2Affine
	if _, err := result.MultiExp(points, scalars, ecc.MultiExpConfig{}); err != nil {
		return nil, err
	}
	return encodeG2(&result), nil
}

func pairingCheck(in []byte) ([]byte, error) {
	if len(in) == 0 || len(in)%pairingSetSize != 0 {
		return nil, errors.New("invalid pairing input length")
	}
	count := len(in) / pairingSetSize
	g1Points := make([]bls12381.G1Affine, count)
	g2Points := make([]bls12381.G2Affine, count)
	for i := 0; i < count; i++ {
		offset := i * pairingSetSize
		g1Point, err := decodeG1(in[offset : offset+g1EncodedSize])
		if err != nil {
			return nil, err
		}
		if !g1Point.IsInSubGroup() {
			return nil, errors.New("G1 point is not in the correct subgroup")
		}
		g2Point, err := decodeG2(in[offset+g1EncodedSize : offset+pairingSetSize])
		if err != nil {
			return nil, err
		}
		if !g2Point.IsInSubGroup() {
			return nil, errors.New("G2 point is not in the correct subgroup")
		}
		g1Points[i], g2Points[i] = g1Point, g2Point
	}
	// MillerLoop drops pairs containing the point at infinity, so a product
	// made only of such pairs correctly evaluates to one.
	ok, err := bls12381.PairingCheck(g1Points, g2Points)
	if err != nil {
		return nil, err
	}
	out := make([]byte, 32)
	if ok {
		out[31] = 1
	}
	return out, nil
}

func mapFpToG1(in []byte) ([]byte, error) {
	element, err := decodeFp(in)
	if err != nil {
		return nil, err
	}
	point := bls12381.MapToG1(element)
	return encodeG1(&point), nil
}

func mapFp2ToG2(in []byte) ([]byte, error) {
	c0, c1, err := decodeFp2(in)
	if err != nil {
		return nil, err
	}
	var element bls12381.E2
	element.A0, element.A1 = c0, c1
	point := bls12381.MapToG2(element)
	return encodeG2(&point), nil
}

var operations = map[string]func([]byte) ([]byte, error){
	"g1add":      g1Add,
	"g1msm":      g1MSM,
	"g2add":      g2Add,
	"g2msm":      g2MSM,
	"pairing":    pairingCheck,
	"mapfptog1":  mapFpToG1,
	"mapfp2tog2": mapFp2ToG2,
}

func decodeHexPayload(payload string) ([]byte, error) {
	trimmed := strings.TrimPrefix(strings.TrimPrefix(payload, "0x"), "0X")
	if trimmed == "" {
		return []byte{}, nil
	}
	return hex.DecodeString(trimmed)
}

// dispatch resolves one request and returns the hex-encoded response body.
func dispatch(operation, payload string) (string, error) {
	if operation == "ping" {
		return protocolVersion, nil
	}
	handler, ok := operations[operation]
	if !ok {
		return "", fmt.Errorf("unknown operation %q", operation)
	}
	input, err := decodeHexPayload(payload)
	if err != nil {
		return "", errors.New("input is not valid hex")
	}
	output, err := handler(input)
	if err != nil {
		return "", err
	}
	return hex.EncodeToString(output), nil
}

// sanitize keeps an error message on a single line so it cannot corrupt the
// response framing.
func sanitize(message string) string {
	replaced := strings.NewReplacer("\n", " ", "\r", " ").Replace(message)
	return strings.TrimSpace(replaced)
}

func splitRequest(line string) (string, string) {
	fields := strings.Fields(line)
	switch len(fields) {
	case 0:
		return "", ""
	case 1:
		return strings.ToLower(fields[0]), ""
	default:
		return strings.ToLower(fields[0]), fields[1]
	}
}

func respond(writer *bufio.Writer, output string, err error) error {
	if err != nil {
		if _, writeErr := fmt.Fprintf(writer, "err %s\n", sanitize(err.Error())); writeErr != nil {
			return writeErr
		}
	} else if _, writeErr := fmt.Fprintf(writer, "ok %s\n", output); writeErr != nil {
		return writeErr
	}
	return writer.Flush()
}

// serve runs the persistent request loop. A malformed or failing request
// produces an error response and the process stays available for the next one.
func serve(input io.Reader, output io.Writer) error {
	reader := bufio.NewReader(input)
	writer := bufio.NewWriter(output)
	for {
		line, err := reader.ReadString('\n')
		if line != "" {
			operation, payload := splitRequest(line)
			if operation != "" {
				result, dispatchErr := dispatch(operation, payload)
				if respondErr := respond(writer, result, dispatchErr); respondErr != nil {
					return respondErr
				}
			}
		}
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
	}
}

func main() {
	if len(os.Args) > 1 {
		operation, payload := splitRequest(strings.Join(os.Args[1:], " "))
		result, err := dispatch(operation, payload)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s\n", sanitize(err.Error()))
			os.Exit(1)
		}
		fmt.Println(result)
		return
	}
	if err := serve(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", sanitize(err.Error()))
		os.Exit(1)
	}
}
