// Bosch BSEC2 IAQ configuration for BME688/BME680 @ 3.3V, LP (~3s) sample rate.
// Bu blob, Bosch-BSEC2-Library 1.10.2610 içindeki
// `bme680_iaq_33v_3s_28d/bsec_iaq.txt` dosyasından alındı (ESPHome ile aynı).
// Asıl veri `bsec_iaq_esphome.txt` içinde virgülle ayrılmış baytlar olarak
// saklanıyor; burada diziye gömülerek BSEC2.setConfig()'e veriliyor.

#pragma once

#include <stdint.h>

static const uint8_t bsec_config[] = {
#include "bsec_iaq_esphome.txt"
};

static const unsigned int bsec_config_len = sizeof(bsec_config);

