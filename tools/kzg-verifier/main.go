package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	goethkzg "github.com/crate-crypto/go-eth-kzg"
)

const trustedSetupSHA256 = "f8e44a31ebf0a6d0734dcb301b0716e2c77f3ae18ed0cab0870fbcc2ca55616f"

//go:embed trusted_setup.json
var trustedSetupJSON []byte

func decodeFixedHex(input string, size int) ([]byte, error) {
	trimmed := strings.TrimPrefix(strings.TrimPrefix(input, "0x"), "0X")
	decoded, err := hex.DecodeString(trimmed)
	if err != nil {
		return nil, err
	}
	if len(decoded) != size {
		return nil, fmt.Errorf("expected %d bytes, got %d", size, len(decoded))
	}
	return decoded, nil
}

func loadContext() (*goethkzg.Context, error) {
	sum := sha256.Sum256(trustedSetupJSON)
	if hex.EncodeToString(sum[:]) != trustedSetupSHA256 {
		return nil, fmt.Errorf("trusted setup SHA-256 mismatch: got %x", sum)
	}

	var trustedSetup goethkzg.JSONTrustedSetup
	if err := json.Unmarshal(trustedSetupJSON, &trustedSetup); err != nil {
		return nil, err
	}

	return goethkzg.NewContext4096(&trustedSetup)
}

func decodeCommitment(input string) (goethkzg.KZGCommitment, error) {
	var commitment goethkzg.KZGCommitment
	decoded, err := decodeFixedHex(input, len(commitment))
	if err != nil {
		return commitment, err
	}
	copy(commitment[:], decoded)
	return commitment, nil
}

func decodeProof(input string) (goethkzg.KZGProof, error) {
	var proof goethkzg.KZGProof
	decoded, err := decodeFixedHex(input, len(proof))
	if err != nil {
		return proof, err
	}
	copy(proof[:], decoded)
	return proof, nil
}

func decodePoint(input string) (goethkzg.Scalar, error) {
	var point goethkzg.Scalar
	decoded, err := decodeFixedHex(input, len(point))
	if err != nil {
		return point, err
	}
	copy(point[:], decoded)
	return point, nil
}

func decodeClaim(input string) (goethkzg.Scalar, error) {
	var claim goethkzg.Scalar
	decoded, err := decodeFixedHex(input, len(claim))
	if err != nil {
		return claim, err
	}
	copy(claim[:], decoded)
	return claim, nil
}

func decodeBlob(input string) (goethkzg.Blob, error) {
	var blob goethkzg.Blob
	if strings.HasPrefix(input, "@") {
		contents, err := os.ReadFile(strings.TrimPrefix(input, "@"))
		if err != nil {
			return blob, err
		}
		input = strings.TrimSpace(string(contents))
	}
	decoded, err := decodeFixedHex(input, len(blob))
	if err != nil {
		return blob, err
	}
	copy(blob[:], decoded)
	return blob, nil
}

func verifyPoint(ctx *goethkzg.Context, args []string) (bool, error) {
	if len(args) != 4 {
		return false, fmt.Errorf("expected 4 point arguments, got %d", len(args))
	}
	commitment, err := decodeCommitment(args[0])
	if err != nil {
		return false, err
	}
	point, err := decodePoint(args[1])
	if err != nil {
		return false, err
	}
	claim, err := decodeClaim(args[2])
	if err != nil {
		return false, err
	}
	proof, err := decodeProof(args[3])
	if err != nil {
		return false, err
	}
	return ctx.VerifyKZGProof(commitment, point, claim, proof) == nil, nil
}

func verifyBlob(ctx *goethkzg.Context, args []string) (bool, error) {
	if len(args) != 3 {
		return false, fmt.Errorf("expected 3 blob arguments, got %d", len(args))
	}
	blob, err := decodeBlob(args[0])
	if err != nil {
		return false, err
	}
	commitment, err := decodeCommitment(args[1])
	if err != nil {
		return false, err
	}
	proof, err := decodeProof(args[2])
	if err != nil {
		return false, err
	}
	return ctx.VerifyBlobKZGProof(&blob, commitment, proof) == nil, nil
}

func run(args []string) (bool, error) {
	if len(args) == 0 {
		return false, fmt.Errorf("missing verifier mode")
	}

	ctx, err := loadContext()
	if err != nil {
		return false, err
	}

	switch args[0] {
	case "point":
		return verifyPoint(ctx, args[1:])
	case "blob":
		return verifyBlob(ctx, args[1:])
	default:
		return false, fmt.Errorf("unknown verifier mode %q", args[0])
	}
}

func main() {
	valid, err := run(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if valid {
		fmt.Println("true")
	} else {
		fmt.Println("false")
	}
}
