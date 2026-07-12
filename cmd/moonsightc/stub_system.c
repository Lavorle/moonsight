#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
/* Wrapper so MoonBit can call libc system(3) without a symbol clash. */
#include <stdlib.h>

int moonsight_system(const char *cmd) {
  return system(cmd);
}

typedef struct {
  uint32_t state[8];
  uint64_t bit_count;
  uint8_t block[64];
  size_t block_len;
} moonsight_sha256;

static const uint32_t sha256_k[64] = {
  0x428a2f98U,0x71374491U,0xb5c0fbcfU,0xe9b5dba5U,0x3956c25bU,0x59f111f1U,0x923f82a4U,0xab1c5ed5U,
  0xd807aa98U,0x12835b01U,0x243185beU,0x550c7dc3U,0x72be5d74U,0x80deb1feU,0x9bdc06a7U,0xc19bf174U,
  0xe49b69c1U,0xefbe4786U,0x0fc19dc6U,0x240ca1ccU,0x2de92c6fU,0x4a7484aaU,0x5cb0a9dcU,0x76f988daU,
  0x983e5152U,0xa831c66dU,0xb00327c8U,0xbf597fc7U,0xc6e00bf3U,0xd5a79147U,0x06ca6351U,0x14292967U,
  0x27b70a85U,0x2e1b2138U,0x4d2c6dfcU,0x53380d13U,0x650a7354U,0x766a0abbU,0x81c2c92eU,0x92722c85U,
  0xa2bfe8a1U,0xa81a664bU,0xc24b8b70U,0xc76c51a3U,0xd192e819U,0xd6990624U,0xf40e3585U,0x106aa070U,
  0x19a4c116U,0x1e376c08U,0x2748774cU,0x34b0bcb5U,0x391c0cb3U,0x4ed8aa4aU,0x5b9cca4fU,0x682e6ff3U,
  0x748f82eeU,0x78a5636fU,0x84c87814U,0x8cc70208U,0x90befffaU,0xa4506cebU,0xbef9a3f7U,0xc67178f2U
};

static uint32_t rotr32(uint32_t x, unsigned n) { return (x >> n) | (x << (32U - n)); }

static void sha256_transform(moonsight_sha256 *ctx, const uint8_t block[64]) {
  uint32_t w[64];
  for (int i = 0; i < 16; ++i) {
    w[i] = ((uint32_t)block[i * 4] << 24) | ((uint32_t)block[i * 4 + 1] << 16) |
           ((uint32_t)block[i * 4 + 2] << 8) | block[i * 4 + 3];
  }
  for (int i = 16; i < 64; ++i) {
    uint32_t s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a=ctx->state[0], b=ctx->state[1], c=ctx->state[2], d=ctx->state[3];
  uint32_t e=ctx->state[4], f=ctx->state[5], g=ctx->state[6], h=ctx->state[7];
  for (int i = 0; i < 64; ++i) {
    uint32_t s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
    uint32_t ch = (e & f) ^ ((~e) & g);
    uint32_t t1 = h + s1 + ch + sha256_k[i] + w[i];
    uint32_t s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = s0 + maj;
    h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
  }
  ctx->state[0]+=a; ctx->state[1]+=b; ctx->state[2]+=c; ctx->state[3]+=d;
  ctx->state[4]+=e; ctx->state[5]+=f; ctx->state[6]+=g; ctx->state[7]+=h;
}

static void sha256_init(moonsight_sha256 *ctx) {
  static const uint32_t initial[8] = {0x6a09e667U,0xbb67ae85U,0x3c6ef372U,0xa54ff53aU,0x510e527fU,0x9b05688cU,0x1f83d9abU,0x5be0cd19U};
  memcpy(ctx->state, initial, sizeof(initial));
  ctx->bit_count = 0; ctx->block_len = 0;
}

static void sha256_update(moonsight_sha256 *ctx, const uint8_t *data, size_t len) {
  ctx->bit_count += (uint64_t)len * 8U;
  while (len > 0) {
    size_t take = 64U - ctx->block_len;
    if (take > len) take = len;
    memcpy(ctx->block + ctx->block_len, data, take);
    ctx->block_len += take; data += take; len -= take;
    if (ctx->block_len == 64U) { sha256_transform(ctx, ctx->block); ctx->block_len = 0; }
  }
}

static void sha256_final(moonsight_sha256 *ctx, uint8_t out[32]) {
  ctx->block[ctx->block_len++] = 0x80;
  if (ctx->block_len > 56U) {
    memset(ctx->block + ctx->block_len, 0, 64U - ctx->block_len);
    sha256_transform(ctx, ctx->block); ctx->block_len = 0;
  }
  memset(ctx->block + ctx->block_len, 0, 56U - ctx->block_len);
  for (int i = 0; i < 8; ++i) ctx->block[63 - i] = (uint8_t)(ctx->bit_count >> (i * 8));
  sha256_transform(ctx, ctx->block);
  for (int i = 0; i < 8; ++i) {
    out[i*4]=(uint8_t)(ctx->state[i]>>24); out[i*4+1]=(uint8_t)(ctx->state[i]>>16);
    out[i*4+2]=(uint8_t)(ctx->state[i]>>8); out[i*4+3]=(uint8_t)ctx->state[i];
  }
}

int moonsight_sha256_file(const char *path, uint8_t *output_hex) {
  FILE *file = fopen(path, "rb");
  if (!file) return -1;
  moonsight_sha256 ctx; sha256_init(&ctx);
  uint8_t buffer[16384];
  size_t count;
  while ((count = fread(buffer, 1, sizeof(buffer), file)) > 0) sha256_update(&ctx, buffer, count);
  if (ferror(file)) { int saved = errno; fclose(file); errno = saved; return -1; }
  if (fclose(file) != 0) return -1;
  uint8_t digest[32]; sha256_final(&ctx, digest);
  static const char hex[] = "0123456789abcdef";
  for (int i = 0; i < 32; ++i) { output_hex[i*2] = hex[digest[i] >> 4]; output_hex[i*2+1] = hex[digest[i] & 15]; }
  return 0;
}
