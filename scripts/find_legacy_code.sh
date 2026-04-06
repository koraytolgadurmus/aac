#!/bin/bash
# find_legacy_code.sh
# Eski kod kalıntılarını otomatik olarak tespit eder

set -e

# Renkler
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Proje root dizini
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}🔍 Eski Kod Kalıntılarını Tespit Ediyorum...${NC}\n"

# 1. Deprecated/Legacy kelimelerini ara
echo -e "${YELLOW}1. Deprecated/Legacy İşaretli Kodlar:${NC}"
LEGACY_COUNT=$(grep -r -n "deprecated\|legacy\|Legacy\|LEGACY" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" | wc -l)
if [ "$LEGACY_COUNT" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $LEGACY_COUNT satır bulundu${NC}"
    grep -r -n "deprecated\|legacy\|Legacy\|LEGACY" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" | head -20
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 2. TODO/FIXME/XXX/HACK işaretleri
echo -e "${YELLOW}2. TODO/FIXME/XXX/HACK İşaretleri:${NC}"
TODO_COUNT=$(grep -r -n "TODO\|FIXME\|XXX\|HACK" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" | wc -l)
if [ "$TODO_COUNT" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $TODO_COUNT satır bulundu${NC}"
    grep -r -n "TODO\|FIXME\|XXX\|HACK" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" | head -20
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 3. Unused pin/variable tanımları
echo -e "${YELLOW}3. Unused Pin/Variable Tanımları:${NC}"
UNUSED_COUNT=$(grep -r -n "unused\|Unused\|UNUSED" src/ 2>/dev/null | wc -l)
if [ "$UNUSED_COUNT" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $UNUSED_COUNT satır bulundu${NC}"
    grep -r -n "unused\|Unused\|UNUSED" src/ 2>/dev/null | head -10
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 4. Legacy endpoint'ler
echo -e "${YELLOW}4. Legacy HTTP Endpoint'ler:${NC}"
ENDPOINT_COUNT=$(grep -r -n "g_http.on.*deprecated\|Legacy endpoints" src/ 2>/dev/null | wc -l)
if [ "$ENDPOINT_COUNT" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $ENDPOINT_COUNT satır bulundu${NC}"
    grep -r -n "g_http.on.*deprecated\|Legacy endpoints" src/ 2>/dev/null | head -10
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 5. Legacy variable'lar (kMqttHostLegacy, g_ownerHash, etc.)
echo -e "${YELLOW}5. Legacy Variable Tanımları:${NC}"
LEGACY_VARS=$(grep -r -n "kMqttHostLegacy\|g_ownerHash\|legacyUser\|legacyHash\|legacyPlain" src/ 2>/dev/null | wc -l)
if [ "$LEGACY_VARS" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $LEGACY_VARS satır bulundu${NC}"
    grep -r -n "kMqttHostLegacy\|g_ownerHash\|legacyUser\|legacyHash\|legacyPlain" src/ 2>/dev/null | head -15
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 6. Migration code'ları
echo -e "${YELLOW}6. Migration Code'ları:${NC}"
MIGRATION_COUNT=$(grep -r -n "migration\|Migration\|MIGRATION" src/ 2>/dev/null | grep -v "node_modules" | wc -l)
if [ "$MIGRATION_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}   ⚠️  $MIGRATION_COUNT satır bulundu (Migration gerekli olabilir)${NC}"
    grep -r -n "migration\|Migration\|MIGRATION" src/ 2>/dev/null | grep -v "node_modules" | head -10
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 7. Eski credential key'leri (auth_user, auth_pass, etc.)
echo -e "${YELLOW}7. Eski Credential Key Referansları:${NC}"
CRED_KEYS=$(grep -r -n "auth_user\|auth_pass\|admin_user\|admin_pass\|setup_pass_plain" src/ 2>/dev/null | wc -l)
if [ "$CRED_KEYS" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $CRED_KEYS satır bulundu${NC}"
    grep -r -n "auth_user\|auth_pass\|admin_user\|admin_pass\|setup_pass_plain" src/ 2>/dev/null | head -10
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# 8. Hardcoded secret'lar (güvenlik açığı olabilir)
echo -e "${YELLOW}8. Hardcoded Secret'lar (Güvenlik Riski):${NC}"
HARDCODED=$(grep -r -n "password.*=.*[\"'].*[\"']\|token.*=.*[\"'].*[\"']\|key.*=.*[\"'].*[\"']" src/ 2>/dev/null | grep -v "//\|/\*" | wc -l)
if [ "$HARDCODED" -gt 0 ]; then
    echo -e "${RED}   ⚠️  $HARDCODED potansiyel hardcoded secret bulundu${NC}"
    grep -r -n "password.*=.*[\"'].*[\"']\|token.*=.*[\"'].*[\"']\|key.*=.*[\"'].*[\"']" src/ 2>/dev/null | grep -v "//\|/\*" | head -10
    echo ""
else
    echo -e "${GREEN}   ✅ Bulunamadı${NC}\n"
fi

# Özet
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📊 ÖZET${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Legacy/Deprecated:     ${RED}$LEGACY_COUNT${NC}"
echo -e "TODO/FIXME:           ${RED}$TODO_COUNT${NC}"
echo -e "Unused:               ${RED}$UNUSED_COUNT${NC}"
echo -e "Legacy Endpoints:     ${RED}$ENDPOINT_COUNT${NC}"
echo -e "Legacy Variables:      ${RED}$LEGACY_VARS${NC}"
echo -e "Migration Code:       ${YELLOW}$MIGRATION_COUNT${NC}"
echo -e "Eski Credentials:      ${RED}$CRED_KEYS${NC}"
echo -e "Hardcoded Secrets:     ${RED}$HARDCODED${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Detaylı rapor dosyası oluştur
REPORT_FILE="$PROJECT_ROOT/LEGACY_CODE_REPORT_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "Eski Kod Kalıntıları Raporu"
    echo "Tarih: $(date)"
    echo "=========================================="
    echo ""
    echo "1. DEPRECATED/LEGACY İŞARETLİ KODLAR:"
    echo "--------------------------------------"
    grep -r -n "deprecated\|legacy\|Legacy\|LEGACY" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" || echo "Bulunamadı"
    echo ""
    echo "2. TODO/FIXME/XXX/HACK İŞARETLERİ:"
    echo "--------------------------------------"
    grep -r -n "TODO\|FIXME\|XXX\|HACK" src/ cloud/ app/lib/ 2>/dev/null | grep -v "node_modules" || echo "Bulunamadı"
    echo ""
    echo "3. UNUSED PIN/VARIABLE TANIMLARI:"
    echo "--------------------------------------"
    grep -r -n "unused\|Unused\|UNUSED" src/ 2>/dev/null || echo "Bulunamadı"
    echo ""
    echo "4. LEGACY HTTP ENDPOINT'LER:"
    echo "--------------------------------------"
    grep -r -n "g_http.on.*deprecated\|Legacy endpoints" src/ 2>/dev/null || echo "Bulunamadı"
    echo ""
    echo "5. LEGACY VARIABLE TANIMLARI:"
    echo "--------------------------------------"
    grep -r -n "kMqttHostLegacy\|g_ownerHash\|legacyUser\|legacyHash\|legacyPlain" src/ 2>/dev/null || echo "Bulunamadı"
    echo ""
    echo "6. MIGRATION CODE'LARI:"
    echo "--------------------------------------"
    grep -r -n "migration\|Migration\|MIGRATION" src/ 2>/dev/null | grep -v "node_modules" || echo "Bulunamadı"
    echo ""
    echo "7. ESKİ CREDENTIAL KEY REFERANSLARI:"
    echo "--------------------------------------"
    grep -r -n "auth_user\|auth_pass\|admin_user\|admin_pass\|setup_pass_plain" src/ 2>/dev/null || echo "Bulunamadı"
    echo ""
    echo "8. HARDCODED SECRET'LAR:"
    echo "--------------------------------------"
    grep -r -n "password.*=.*[\"'].*[\"']\|token.*=.*[\"'].*[\"']\|key.*=.*[\"'].*[\"']" src/ 2>/dev/null | grep -v "//\|/\*" || echo "Bulunamadı"
} > "$REPORT_FILE"

echo -e "${GREEN}✅ Detaylı rapor oluşturuldu: $REPORT_FILE${NC}\n"

# Öneriler
echo -e "${BLUE}💡 ÖNERİLER:${NC}"
if [ "$LEGACY_COUNT" -gt 50 ]; then
    echo -e "   • ${YELLOW}Çok sayıda legacy kod bulundu. Kademeli temizlik yapın.${NC}"
fi
if [ "$ENDPOINT_COUNT" -gt 0 ]; then
    echo -e "   • ${YELLOW}Deprecated endpoint'ler bulundu. Önce 410 Gone döndürün, sonra kaldırın.${NC}"
fi
if [ "$MIGRATION_COUNT" -gt 0 ]; then
    echo -e "   • ${YELLOW}Migration code'ları var. Tüm cihazlar migrate edildiyse kaldırılabilir.${NC}"
fi
if [ "$HARDCODED" -gt 0 ]; then
    echo -e "   • ${RED}Hardcoded secret'lar bulundu! Güvenlik riski! Hemen düzeltin.${NC}"
fi
echo ""

