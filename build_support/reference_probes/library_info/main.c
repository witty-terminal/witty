#include <witty.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    const ghostty_info_s info = ghostty_info();
    assert(info.build_mode == GHOSTTY_BUILD_MODE_RELEASE_SAFE);
    assert(info.version_len == 5 && memcmp(info.version, "1.3.0", 5) == 0);
    char *args[] = {"library-info-probe", "--font-size=17", NULL};
    assert(ghostty_init(2, args) == 0);
    ghostty_config_t config = ghostty_config_new();
    assert(config);
    ghostty_config_load_cli_args(config);
    ghostty_config_finalize(config);
    float font_size = 0;
    assert(ghostty_config_get(config, &font_size, "font-size", 9));
    assert(font_size == 17);
    ghostty_config_free(config);
    printf("mode=%d version=%.*s font-size=%.0f\n", info.build_mode,
           (int)info.version_len, info.version, font_size);
    return 0;
}
