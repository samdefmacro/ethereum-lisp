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
