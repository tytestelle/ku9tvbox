#!/bin/bash
set -e

KU9="$1"
TVBOX="$2"
OUT="$3"

echo "========================================"
echo "  重铸酷9 - 基于实际仓库结构"
echo "========================================"
echo "酷9: $KU9 (单模块, Java已混淆)"
echo "TVBoxOS: $TVBOX (多模块: app/player/quickjs/pyramid)"
echo "输出: $OUT"
echo ""

# 1. 复制TVBoxOS作为完整骨架
echo "[1/5] 复制TVBoxOS骨架..."
cp -r "$TVBOX" "$OUT"

# 2. 替换酷9的UI资源 (res + assets)
echo "[2/5] 移植酷9 UI资源..."
cp -r "$KU9/app/src/main/res" "$OUT/app/src/main/"
cp -r "$KU9/app/src/main/assets" "$OUT/app/src/main/" 2>/dev/null || true

# 3. 替换AndroidManifest.xml
echo "[3/5] 移植AndroidManifest.xml..."
cp "$KU9/app/src/main/AndroidManifest.xml" "$OUT/app/src/main/"

# 4. 复制酷9的jniLibs和libs (如果有)
echo "[4/5] 移植jniLibs和libs..."
cp -r "$KU9/app/src/main/jniLibs" "$OUT/app/src/main/" 2>/dev/null || true
cp -r "$KU9/app/libs" "$OUT/app/" 2>/dev/null || true

# 5. 备份酷9的混淆Java代码（但不覆盖TVBoxOS标准代码）
echo "[5/5] 备份混淆Java代码..."
mkdir -p "$OUT/ku9_obfuscated_java"
cp -r "$KU9/app/src/main/java" "$OUT/ku9_obfuscated_java/" 2>/dev/null || true
echo "  -> TVBoxOS标准Java代码保留在 app/src/main/java/"
echo "  -> 酷9混淆代码备份到 ku9_obfuscated_java/"

# 清理潜在的R.java残留
find "$OUT/app/src/main/java" -name "R*.java" -delete 2>/dev/null || true

# 生成简要报告
cat > "$OUT/MERGE_REPORT.md" << EOF
# 重铸报告

- 生成时间: $(date)
- 酷9仓库: $KU9
- TVBoxOS仓库: $TVBOX

## 替换内容
- ✅ 资源 (res/) 来自酷9
- ✅ assets/ 来自酷9
- ✅ AndroidManifest.xml 来自酷9
- ✅ jniLibs/ 和 libs/ 来自酷9 (若有)
- ✅ Java 代码使用 TVBoxOS 标准版本 (因为酷9代码已混淆)
- 📁 酷9混淆代码已备份到 ku9_obfuscated_java/

## 编译命令
\`\`\`bash
cd $OUT
./gradlew :app:assembleJavaDebug
\`\`\`
EOF

echo ""
echo "========================================"
echo "  重铸完成！"
echo "========================================"
echo "输出目录: $OUT"
