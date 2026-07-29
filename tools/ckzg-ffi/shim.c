/*
 * A minimal, stable C ABI over c-kzg-4844 for the CFFI binding.
 *
 * The KZGSettings struct is opaque and version-dependent, so it is never
 * exposed to Lisp: this shim allocates and owns it and hands back a void*.
 * The verify entry points take raw byte pointers and return a small tri-state
 * int (1 valid, 0 invalid, -1 error), which is trivial to bind and leaves the
 * EIP-4844 size and enum details on the C side.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "ckzg.h"

/* Load the trusted setup from PATH; returns an owning handle or NULL. */
void *eth_ckzg_load_setup(const char *path, uint64_t precompute) {
    KZGSettings *settings = malloc(sizeof(KZGSettings));
    if (settings == NULL) {
        return NULL;
    }
    FILE *file = fopen(path, "r");
    if (file == NULL) {
        free(settings);
        return NULL;
    }
    C_KZG_RET ret = load_trusted_setup_file(settings, file, precompute);
    fclose(file);
    if (ret != C_KZG_OK) {
        free(settings);
        return NULL;
    }
    return settings;
}

void eth_ckzg_free_setup(void *handle) {
    if (handle != NULL) {
        free_trusted_setup((KZGSettings *)handle);
        free(handle);
    }
}

/* EIP-4844 point evaluation. 1 = valid, 0 = invalid, -1 = malformed input. */
int eth_ckzg_verify_kzg_proof(void *handle, const uint8_t *commitment,
                              const uint8_t *z, const uint8_t *y,
                              const uint8_t *proof) {
    bool ok = false;
    C_KZG_RET ret = verify_kzg_proof(
        &ok, (const Bytes48 *)commitment, (const Bytes32 *)z,
        (const Bytes32 *)y, (const Bytes48 *)proof, (const KZGSettings *)handle);
    if (ret != C_KZG_OK) {
        return -1;
    }
    return ok ? 1 : 0;
}

/* EIP-4844 blob proof. 1 = valid, 0 = invalid, -1 = malformed input. */
int eth_ckzg_verify_blob_kzg_proof(void *handle, const uint8_t *blob,
                                   const uint8_t *commitment,
                                   const uint8_t *proof) {
    bool ok = false;
    C_KZG_RET ret = verify_blob_kzg_proof(
        &ok, (const Blob *)blob, (const Bytes48 *)commitment,
        (const Bytes48 *)proof, (const KZGSettings *)handle);
    if (ret != C_KZG_OK) {
        return -1;
    }
    return ok ? 1 : 0;
}

/* EIP-7594: verify every extended-blob cell proof against one commitment. */
int eth_ckzg_verify_blob_cell_proofs(void *handle, const uint8_t *blob,
                                     const uint8_t *commitment,
                                     const uint8_t *proofs) {
    Cell *cells = malloc(CELLS_PER_EXT_BLOB * sizeof(Cell));
    Bytes48 *commitments = malloc(CELLS_PER_EXT_BLOB * sizeof(Bytes48));
    uint64_t *indices = malloc(CELLS_PER_EXT_BLOB * sizeof(uint64_t));
    bool ok = false;
    C_KZG_RET ret;

    if (cells == NULL || commitments == NULL || indices == NULL) {
        free(cells);
        free(commitments);
        free(indices);
        return -1;
    }
    ret = compute_cells_and_kzg_proofs(
        cells, NULL, (const Blob *)blob, (const KZGSettings *)handle);
    if (ret == C_KZG_OK) {
        for (uint64_t i = 0; i < CELLS_PER_EXT_BLOB; i++) {
            commitments[i] = *(const Bytes48 *)commitment;
            indices[i] = i;
        }
        ret = verify_cell_kzg_proof_batch(
            &ok, commitments, indices, cells, (const Bytes48 *)proofs,
            CELLS_PER_EXT_BLOB, (const KZGSettings *)handle);
    }
    free(cells);
    free(commitments);
    free(indices);
    if (ret != C_KZG_OK) {
        return -1;
    }
    return ok ? 1 : 0;
}

/* EIP-7594: compute the 128 cell proofs for one blob into caller storage. */
int eth_ckzg_compute_blob_cell_proofs(void *handle, const uint8_t *blob,
                                      uint8_t *proofs) {
    Cell *cells = malloc(CELLS_PER_EXT_BLOB * sizeof(Cell));
    C_KZG_RET ret;

    if (cells == NULL) {
        return -1;
    }
    ret = compute_cells_and_kzg_proofs(
        cells, (Bytes48 *)proofs, (const Blob *)blob,
        (const KZGSettings *)handle);
    free(cells);
    return ret == C_KZG_OK ? 1 : -1;
}

/* EIP-7594 cell computation. 1 = success, -1 = malformed input/error. */
int eth_ckzg_compute_cells_and_proofs(void *handle, const uint8_t *blob,
                                      uint8_t *cells, uint8_t *proofs) {
    C_KZG_RET ret = compute_cells_and_kzg_proofs(
        (Cell *)cells, (KZGProof *)proofs, (const Blob *)blob,
        (const KZGSettings *)handle);
    return ret == C_KZG_OK ? 1 : -1;
}
