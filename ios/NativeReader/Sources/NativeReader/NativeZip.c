#include <stdint.h>
#include <stddef.h>
#include <limits.h>
#include <string.h>
#include <zlib.h>

int fq_native_inflate_zip_data(int method, const uint8_t *source, size_t source_len,
                               uint8_t *destination, size_t destination_len,
                               uint32_t expected_crc32) {
    if ((!source && source_len) || (!destination && destination_len) ||
        source_len > UINT_MAX || destination_len > UINT_MAX) return -1;

    if (method == 0) {
        if (source_len != destination_len) return -2;
        if (source_len) memcpy(destination, source, source_len);
    } else if (method == 8) {
        z_stream stream;
        memset(&stream, 0, sizeof(stream));
        stream.next_in = (Bytef *)source;
        stream.avail_in = (uInt)source_len;
        stream.next_out = destination;
        stream.avail_out = (uInt)destination_len;
        int status = inflateInit2(&stream, -MAX_WBITS);
        if (status != Z_OK) return -3;
        status = inflate(&stream, Z_FINISH);
        int valid = status == Z_STREAM_END && stream.total_out == destination_len && stream.total_in == source_len;
        inflateEnd(&stream);
        if (!valid) return -4;
    } else {
        return -5;
    }

    const uLong actual_crc = crc32(0L, destination, (uInt)destination_len);
    return (uint32_t)actual_crc == expected_crc32 ? 0 : -6;
}
