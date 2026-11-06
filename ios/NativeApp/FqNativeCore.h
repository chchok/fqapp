#ifndef FQ_NATIVE_CORE_H
#define FQ_NATIVE_CORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
char *fq_native_set_device_pool_key(const uint8_t *key, size_t key_len);
char *fq_native_init(const char *config, const char *pool, const char *filters, const char *runtime_dir, uint16_t port);
char *fq_native_request(const char *method, const char *path, const char *query, const uint8_t *body, size_t body_len);
char *fq_native_shutdown(void);
void fq_native_string_free(char *value);
#ifdef __cplusplus
}
#endif
#endif
