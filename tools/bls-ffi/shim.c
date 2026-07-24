/*
 * EIP-2537 BLS12-381 operations over blst, with a stable byte-in/byte-out ABI
 * for the CFFI binding. This mirrors tools/bls12381/main.go exactly: the same
 * encoding, the same point-validity and subgroup rules, the same infinity
 * conventions. blst does the field and curve arithmetic; this file owns only
 * the EIP-2537 serialization and validation.
 *
 * Every entry point returns 0 on success (OUT filled with the operation's
 * fixed-size output) or -1 when the input is invalid, which the precompile
 * turns into a failure. Output sizes: g1* -> 128, g2* -> 256, pairing -> 32.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "blst.h"

#define FP_SIZE 64
#define FP2_SIZE 128
#define G1_SIZE 128
#define G2_SIZE 256
#define SCALAR_SIZE 32
#define G1_MSM_PAIR (G1_SIZE + SCALAR_SIZE) /* 160 */
#define G2_MSM_PAIR (G2_SIZE + SCALAR_SIZE) /* 288 */
#define PAIRING_SET (G1_SIZE + G2_SIZE)     /* 384 */

/* BLS12-381 base field modulus p, big-endian (48 bytes). */
static const uint8_t BLS12_381_P[48] = {
    0x1a, 0x01, 0x11, 0xea, 0x39, 0x7f, 0xe6, 0x9a, 0x4b, 0x1b, 0xa7, 0xb6,
    0x43, 0x4b, 0xac, 0xd7, 0x64, 0x77, 0x4b, 0x84, 0xf3, 0x85, 0x12, 0xbf,
    0x67, 0x30, 0xd2, 0xa0, 0xf6, 0xb0, 0xf6, 0x24, 0x1e, 0xab, 0xff, 0xfe,
    0xb1, 0x53, 0xff, 0xff, 0xb9, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xaa, 0xab};

/* Decode a 64-byte field element: 16 zero bytes, then a 48-byte big-endian
 * value strictly below the modulus. */
static int decode_fp(const uint8_t *in, blst_fp *out) {
    for (int i = 0; i < FP_SIZE - 48; i++) {
        if (in[i] != 0) {
            return -1; /* non-zero padding */
        }
    }
    const uint8_t *be = in + (FP_SIZE - 48);
    for (int i = 0; i < 48; i++) {
        if (be[i] < BLS12_381_P[i]) {
            break; /* canonical */
        }
        if (be[i] > BLS12_381_P[i]) {
            return -1; /* >= modulus */
        }
        if (i == 47) {
            return -1; /* exactly equal to the modulus */
        }
    }
    blst_fp_from_bendian(out, be);
    return 0;
}

static void encode_fp(const blst_fp *in, uint8_t *out) {
    memset(out, 0, FP_SIZE - 48);
    blst_bendian_from_fp(out + (FP_SIZE - 48), in);
}

static int all_zero(const uint8_t *in, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (in[i] != 0) {
            return 0;
        }
    }
    return 1;
}

/* Decode a 128-byte G1 point. An all-zero encoding is the point at infinity
 * (*is_inf set); any other point must lie on the curve. */
static int decode_g1(const uint8_t *in, blst_p1_affine *out, int *is_inf) {
    if (decode_fp(in, &out->x) != 0) {
        return -1;
    }
    if (decode_fp(in + FP_SIZE, &out->y) != 0) {
        return -1;
    }
    if (all_zero(in, G1_SIZE)) {
        *is_inf = 1;
        return 0;
    }
    *is_inf = 0;
    if (!blst_p1_affine_on_curve(out)) {
        return -1;
    }
    return 0;
}

static void encode_g1(const blst_p1_affine *point, uint8_t *out) {
    if (blst_p1_affine_is_inf(point)) {
        memset(out, 0, G1_SIZE);
        return;
    }
    encode_fp(&point->x, out);
    encode_fp(&point->y, out + FP_SIZE);
}

/* Decode a 256-byte G2 point (X.c0, X.c1, Y.c0, Y.c1). */
static int decode_g2(const uint8_t *in, blst_p2_affine *out, int *is_inf) {
    if (decode_fp(in, &out->x.fp[0]) != 0) {
        return -1;
    }
    if (decode_fp(in + FP_SIZE, &out->x.fp[1]) != 0) {
        return -1;
    }
    if (decode_fp(in + FP2_SIZE, &out->y.fp[0]) != 0) {
        return -1;
    }
    if (decode_fp(in + FP2_SIZE + FP_SIZE, &out->y.fp[1]) != 0) {
        return -1;
    }
    if (all_zero(in, G2_SIZE)) {
        *is_inf = 1;
        return 0;
    }
    *is_inf = 0;
    if (!blst_p2_affine_on_curve(out)) {
        return -1;
    }
    return 0;
}

static void encode_g2(const blst_p2_affine *point, uint8_t *out) {
    if (blst_p2_affine_is_inf(point)) {
        memset(out, 0, G2_SIZE);
        return;
    }
    encode_fp(&point->x.fp[0], out);
    encode_fp(&point->x.fp[1], out + FP_SIZE);
    encode_fp(&point->y.fp[0], out + FP2_SIZE);
    encode_fp(&point->y.fp[1], out + FP2_SIZE + FP_SIZE);
}

int eth_bls_g1add(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len != 2 * G1_SIZE) {
        return -1;
    }
    blst_p1_affine a, b;
    int a_inf, b_inf;
    if (decode_g1(in, &a, &a_inf) != 0) {
        return -1;
    }
    if (decode_g1(in + G1_SIZE, &b, &b_inf) != 0) {
        return -1;
    }
    /* EIP-2537 specifies no subgroup check for the addition precompiles. */
    blst_p1 a_proj, sum;
    blst_p1_from_affine(&a_proj, &a);
    blst_p1_add_or_double_affine(&sum, &a_proj, &b);
    blst_p1_affine result;
    blst_p1_to_affine(&result, &sum);
    encode_g1(&result, out);
    return 0;
}

int eth_bls_g2add(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len != 2 * G2_SIZE) {
        return -1;
    }
    blst_p2_affine a, b;
    int a_inf, b_inf;
    if (decode_g2(in, &a, &a_inf) != 0) {
        return -1;
    }
    if (decode_g2(in + G2_SIZE, &b, &b_inf) != 0) {
        return -1;
    }
    blst_p2 a_proj, sum;
    blst_p2_from_affine(&a_proj, &a);
    blst_p2_add_or_double_affine(&sum, &a_proj, &b);
    blst_p2_affine result;
    blst_p2_to_affine(&result, &sum);
    encode_g2(&result, out);
    return 0;
}

int eth_bls_g1msm(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len == 0 || in_len % G1_MSM_PAIR != 0) {
        return -1;
    }
    size_t count = in_len / G1_MSM_PAIR;
    blst_p1 acc;
    int have_acc = 0;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *pair = in + i * G1_MSM_PAIR;
        blst_p1_affine point;
        int is_inf;
        if (decode_g1(pair, &point, &is_inf) != 0) {
            return -1;
        }
        if (!is_inf && !blst_p1_affine_in_g1(&point)) {
            return -1; /* not in the correct subgroup */
        }
        if (is_inf) {
            continue; /* scalar * infinity = infinity */
        }
        blst_scalar scalar;
        blst_scalar_from_bendian(&scalar, pair + G1_SIZE);
        blst_p1 point_proj, term;
        blst_p1_from_affine(&point_proj, &point);
        blst_p1_mult(&term, &point_proj, scalar.b, 256);
        if (!have_acc) {
            acc = term;
            have_acc = 1;
        } else {
            blst_p1_add_or_double(&acc, &acc, &term);
        }
    }
    if (!have_acc) {
        memset(out, 0, G1_SIZE); /* all terms were infinity */
        return 0;
    }
    blst_p1_affine result;
    blst_p1_to_affine(&result, &acc);
    encode_g1(&result, out);
    return 0;
}

int eth_bls_g2msm(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len == 0 || in_len % G2_MSM_PAIR != 0) {
        return -1;
    }
    size_t count = in_len / G2_MSM_PAIR;
    blst_p2 acc;
    int have_acc = 0;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *pair = in + i * G2_MSM_PAIR;
        blst_p2_affine point;
        int is_inf;
        if (decode_g2(pair, &point, &is_inf) != 0) {
            return -1;
        }
        if (!is_inf && !blst_p2_affine_in_g2(&point)) {
            return -1;
        }
        if (is_inf) {
            continue;
        }
        blst_scalar scalar;
        blst_scalar_from_bendian(&scalar, pair + G2_SIZE);
        blst_p2 point_proj, term;
        blst_p2_from_affine(&point_proj, &point);
        blst_p2_mult(&term, &point_proj, scalar.b, 256);
        if (!have_acc) {
            acc = term;
            have_acc = 1;
        } else {
            blst_p2_add_or_double(&acc, &acc, &term);
        }
    }
    if (!have_acc) {
        memset(out, 0, G2_SIZE);
        return 0;
    }
    blst_p2_affine result;
    blst_p2_to_affine(&result, &acc);
    encode_g2(&result, out);
    return 0;
}

int eth_bls_pairing(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len == 0 || in_len % PAIRING_SET != 0) {
        return -1;
    }
    size_t count = in_len / PAIRING_SET;
    blst_fp12 acc = *blst_fp12_one();
    for (size_t i = 0; i < count; i++) {
        const uint8_t *set = in + i * PAIRING_SET;
        blst_p1_affine g1;
        int g1_inf;
        if (decode_g1(set, &g1, &g1_inf) != 0) {
            return -1;
        }
        if (!g1_inf && !blst_p1_affine_in_g1(&g1)) {
            return -1;
        }
        blst_p2_affine g2;
        int g2_inf;
        if (decode_g2(set + G1_SIZE, &g2, &g2_inf) != 0) {
            return -1;
        }
        if (!g2_inf && !blst_p2_affine_in_g2(&g2)) {
            return -1;
        }
        /* e(inf, Q) = e(P, inf) = 1, so such pairs are dropped. */
        if (g1_inf || g2_inf) {
            continue;
        }
        blst_fp12 miller;
        blst_miller_loop(&miller, &g2, &g1);
        blst_fp12_mul(&acc, &acc, &miller);
    }
    blst_fp12 result;
    blst_final_exp(&result, &acc);
    memset(out, 0, 32);
    if (blst_fp12_is_one(&result)) {
        out[31] = 1;
    }
    return 0;
}

int eth_bls_mapfptog1(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len != FP_SIZE) {
        return -1;
    }
    blst_fp u;
    if (decode_fp(in, &u) != 0) {
        return -1;
    }
    blst_p1 point;
    blst_map_to_g1(&point, &u, NULL);
    blst_p1_affine result;
    blst_p1_to_affine(&result, &point);
    encode_g1(&result, out);
    return 0;
}

int eth_bls_mapfp2tog2(const uint8_t *in, size_t in_len, uint8_t *out) {
    if (in_len != FP2_SIZE) {
        return -1;
    }
    blst_fp2 u;
    if (decode_fp(in, &u.fp[0]) != 0) {
        return -1;
    }
    if (decode_fp(in + FP_SIZE, &u.fp[1]) != 0) {
        return -1;
    }
    blst_p2 point;
    blst_map_to_g2(&point, &u, NULL);
    blst_p2_affine result;
    blst_p2_to_affine(&result, &point);
    encode_g2(&result, out);
    return 0;
}
