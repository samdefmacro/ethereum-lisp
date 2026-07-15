(in-package #:ethereum-lisp.crypto)

(defconstant +uint64-mask+ #xffffffffffffffff)

(defconstant +uint32-mask+ #xffffffff)

(defconstant +keccak-256-rate+ 136)

(defconstant +kzg-commitment-size+ 48)

(defconstant +kzg-commitment-version+ #x01)

(defconstant +secp256k1-p+
  #xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f)

(defconstant +secp256k1-n+
  #xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141)

(defconstant +secp256k1-half-n+
  (floor +secp256k1-n+ 2))

(defconstant +secp256k1-gx+
  #x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798)

(defconstant +secp256k1-gy+
  #x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8)

(defparameter +ripemd160-initial-hash+
  #(#x67452301 #xefcdab89 #x98badcfe #x10325476 #xc3d2e1f0))

(defparameter +ripemd160-left-words+
  #(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
    7 4 13 1 10 6 15 3 12 0 9 5 2 14 11 8
    3 10 14 4 9 15 8 1 2 7 0 6 13 11 5 12
    1 9 11 10 0 8 12 4 13 3 7 15 14 5 6 2
    4 0 5 9 7 12 2 10 14 1 3 8 11 6 15 13))

(defparameter +ripemd160-right-words+
  #(5 14 7 0 9 2 11 4 13 6 15 8 1 10 3 12
    6 11 3 7 0 13 5 10 14 15 8 12 4 9 1 2
    15 5 1 3 7 14 6 9 11 8 12 2 10 0 4 13
    8 6 4 1 3 11 15 0 5 12 2 13 9 7 10 14
    12 15 10 4 1 5 8 7 6 2 13 14 0 3 9 11))

(defparameter +ripemd160-left-shifts+
  #(11 14 15 12 5 8 7 9 11 13 14 15 6 7 9 8
    7 6 8 13 11 9 7 15 7 12 15 9 11 7 13 12
    11 13 6 7 14 9 13 15 14 8 13 6 5 12 7 5
    11 12 14 15 14 15 9 8 9 14 5 6 8 6 5 12
    9 15 5 11 6 8 13 12 5 12 13 14 11 8 5 6))

(defparameter +ripemd160-right-shifts+
  #(8 9 9 11 13 15 15 5 7 7 8 11 14 14 12 6
    9 13 15 7 12 8 9 11 7 7 12 7 6 15 13 11
    9 7 15 11 8 6 6 14 12 13 5 14 13 13 7 5
    15 5 8 11 14 14 6 14 6 9 12 9 12 5 15 8
    8 5 12 9 12 5 14 6 8 13 6 5 15 13 11 11))

(defparameter +keccak-round-constants+
  #(#x0000000000000001 #x0000000000008082 #x800000000000808a
    #x8000000080008000 #x000000000000808b #x0000000080000001
    #x8000000080008081 #x8000000000008009 #x000000000000008a
    #x0000000000000088 #x0000000080008009 #x000000008000000a
    #x000000008000808b #x800000000000008b #x8000000000008089
    #x8000000000008003 #x8000000000008002 #x8000000000000080
    #x000000000000800a #x800000008000000a #x8000000080008081
    #x8000000000008080 #x0000000080000001 #x8000000080008008))

(defparameter +keccak-rotation-offsets+
  #(0 1 62 28 27
    36 44 6 55 20
    3 10 43 25 39
    41 45 15 21 8
    18 2 61 56 14))

(defparameter +sha256-initial-hash+
  #(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(defparameter +sha256-round-constants+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
    #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3
    #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
    #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
    #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
    #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
    #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
    #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208
    #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))
