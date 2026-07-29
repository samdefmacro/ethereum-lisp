package discv5interop

import (
	"encoding/hex"
	"testing"

	"github.com/ethereum/go-ethereum/common/mclock"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/p2p/discover/v5wire"
	"github.com/ethereum/go-ethereum/p2p/enode"
)

// This is the same byte-exact WHOAREYOU vector encoded by the Common Lisp
// DISCV5-OFFICIAL-PING-AND-WHOAREYOU-PACKET-VECTORS test. Decoding it through
// pinned geth proves the independently implemented header masking and authdata
// layout agree at the public wire boundary.
const whoareyouHex = "" +
	"00000000000000000000000000000000088b3d434277464933a1ccc59f5967ad" +
	"1d6035f15e528627dde75cd68292f9e6c27d6b66c8100a873fcbaed4e16b8d"

func TestPinnedGethDecodesEthereumLispWhoareyou(t *testing.T) {
	key, err := crypto.HexToECDSA(
		"66fb62bfbd66b9177a138c1e5cddbe4f7c30c343e94e68df8769459cb1cde628",
	)
	if err != nil {
		t.Fatal(err)
	}
	db, err := enode.OpenDB("")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	codec := v5wire.NewCodec(enode.NewLocalNode(db, key), key, mclock.System{}, nil)
	packetBytes, err := hex.DecodeString(whoareyouHex)
	if err != nil {
		t.Fatal(err)
	}
	_, _, packet, err := codec.Decode(packetBytes, "127.0.0.1:30303")
	if err != nil {
		t.Fatalf("pinned geth 38271784 rejected ethereum-lisp packet: %v", err)
	}
	challenge, ok := packet.(*v5wire.Whoareyou)
	if !ok {
		t.Fatalf("decoded packet type %T, want *v5wire.Whoareyou", packet)
	}
	if challenge.RecordSeq != 0 {
		t.Fatalf("record sequence %d, want 0", challenge.RecordSeq)
	}
	wantNonce := [16]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	if challenge.IDNonce != wantNonce {
		t.Fatalf("identity nonce %x, want %x", challenge.IDNonce, wantNonce)
	}
}
