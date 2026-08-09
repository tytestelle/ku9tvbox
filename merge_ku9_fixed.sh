#!/bin/bash
# =============================================================================
# 修复版: 酷9外壳 + TVBoxOS完整源码 + ijkplayer
# 修复: local.properties缺失、文件替换不全、报告生成错误
# =============================================================================

set -e

KU9_DIR="${1:-./080java}"
TVBOX_DIR="${2:-./TVBoxOS}"
OUTPUT_DIR="${3:-./ku9-final}"
IJKPLAYER_DIR="${4:-}"

KU9_APP="$KU9_DIR/app"
TVBOX_APP="$TVBOX_DIR/app"
OUTPUT_APP="$OUTPUT_DIR/app"

echo "========================================"
echo "  酷9 + TVBoxOS + ijkplayer [修复版]"
echo "========================================"
echo ""

if [ ! -d "$KU9_DIR" ]; then echo "[错误] 找不到 080java: $KU9_DIR"; exit 1; fi
if [ ! -d "$TVBOX_DIR" ]; then echo "[错误] 找不到 TVBoxOS: $TVBOX_DIR"; exit 1; fi

# ============================================================================
# Phase 1: 复制080java作为外壳基底
# ============================================================================
echo "[Phase 1/10] 复制080java作为外壳基底..."
rm -rf "$OUTPUT_DIR"
cp -r "$KU9_DIR" "$OUTPUT_DIR"

# ============================================================================
# Phase 2: 复制TVBoxOS的完整构建系统
# ============================================================================
echo "[Phase 2/10] 复制TVBoxOS构建系统..."

for item in gradlew gradle settings.gradle gradle.properties build.gradle local.properties; do
    src="$TVBOX_DIR/$item"
    dst="$OUTPUT_DIR/$item"
    if [ -e "$src" ]; then
        if [ -d "$src" ]; then
            rm -rf "$dst"
            cp -r "$src" "$dst"
        else
            cp "$src" "$dst"
        fi
        echo "  -> $item 已复制"
    fi
done
chmod +x "$OUTPUT_DIR/gradlew" 2>/dev/null || true

# 如果TVBoxOS没有local.properties，创建一个（pyramid模块需要）
if [ ! -f "$OUTPUT_DIR/local.properties" ]; then
    # 尝试从环境变量获取SDK路径
    SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    if [ -d "$SDK_DIR" ]; then
        echo "sdk.dir=$SDK_DIR" > "$OUTPUT_DIR/local.properties"
        echo "  -> local.properties 已创建 (sdk.dir=$SDK_DIR)"
    else
        echo "  [警告] 找不到Android SDK，local.properties未创建"
    fi
fi

# ============================================================================
# Phase 3: 复制TVBoxOS的子模块
# ============================================================================
echo "[Phase 3/10] 复制TVBoxOS子模块..."

for module in "$TVBOX_DIR"/*; do
    module_name=$(basename "$module")
    if [ ! -d "$module" ] || [ "$module_name" = "app" ]; then
        continue
    fi
    if echo "$module_name" | grep -qE "^\.|\.git|\.github|docs|README|LICENSE"; then
        continue
    fi
    if [ -f "$module/build.gradle" ]; then
        dst="$OUTPUT_DIR/$module_name"
        rm -rf "$dst"
        cp -r "$module" "$dst"
        echo "  -> 模块 $module_name 已复制"
    fi
done

# ============================================================================
# Phase 4: 复制app的libs/jniLibs/assets
# ============================================================================
echo "[Phase 4/10] 复制app的libs/jniLibs/assets..."

for dir in libs "src/main/jniLibs" "src/main/assets"; do
    src="$TVBOX_APP/$dir"
    dst="$OUTPUT_APP/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -r "$src/"* "$dst/" 2>/dev/null || true
        echo "  -> app/$dir 已复制"
    fi
done

# ============================================================================
# Phase 5: 核心 - 用TVBoxOS源码替换080java反编译代码
# ============================================================================
echo "[Phase 5/10] 核心: 替换反编译代码..."

KU9_JAVA="$KU9_APP/src/main/java/com/github/tvbox/osc"
TVBOX_JAVA="$TVBOX_APP/src/main/java/com/github/tvbox/osc"
OUTPUT_JAVA="$OUTPUT_APP/src/main/java/com/github/tvbox/osc"

REPLACED=0
ADDED=0

if [ -d "$TVBOX_JAVA" ]; then
    while IFS= read -r src_file; do
        rel_path="${src_file#$TVBOX_JAVA/}"
        dst_file="$OUTPUT_JAVA/$rel_path"

        if [ -f "$dst_file" ]; then
            cp "$src_file" "$dst_file"
            REPLACED=$((REPLACED + 1))
        else
            mkdir -p "$(dirname "$dst_file")"
            cp "$src_file" "$dst_file"
            ADDED=$((ADDED + 1))
        fi
    done < <(find "$TVBOX_JAVA" -name "*.java")
fi

echo "  -> 替换了 $REPLACED 个文件，新增了 $ADDED 个文件"

# ============================================================================
# Phase 6: 额外处理 - 080java中可能存在的其他路径的反编译代码
# ============================================================================
echo "[Phase 6/10] 检查080java中的其他Java代码路径..."

# 080java可能把代码放在其他包名下（如com.player.ku9py）
EXTRA_REPLACED=0

# 扫描080java中所有.java文件，找出TVBoxOS中没有的"额外"文件
if [ -d "$KU9_APP/src/main/java" ] && [ -d "$TVBOX_APP/src/main/java" ]; then
    while IFS= read -r ku9_java_file; do
        rel_path="${ku9_java_file#$KU9_APP/src/main/java/}"
        # 如果已经在com.github.tvbox.osc下，已在Phase 5处理过
        if echo "$rel_path" | grep -q "^com/github/tvbox/osc"; then
            continue
        fi
        # 跳过R.java
        if echo "$rel_path" | grep -qE "(^|/)R\$"; then continue; fi
        if echo "$rel_path" | grep -qE "(^|/)R\.java$"; then continue; fi

        # 这是080java中其他包名下的文件，保留
        dst="$OUTPUT_APP/src/main/java/$rel_path"
        if [ -f "$ku9_java_file" ] && [ ! -f "$dst" ]; then
            mkdir -p "$(dirname "$dst")"
            cp "$ku9_java_file" "$dst"
            EXTRA_REPLACED=$((EXTRA_REPLACED + 1))
        fi
    done < <(find "$KU9_APP/src/main/java" -name "*.java" 2>/dev/null || true)
fi

if [ $EXTRA_REPLACED -gt 0 ]; then
    echo "  -> 额外保留了 $EXTRA_REPLACED 个非标准路径的Java文件"
fi

# ============================================================================
# Phase 7: 清理反编译垃圾 + 处理ijkplayer
# ============================================================================
echo "[Phase 7/10] 清理反编译产物..."

R_CLEANED=0
if [ -d "$OUTPUT_APP/src/main/java" ]; then
    while IFS= read -r rfile; do
        rm "$rfile"
        R_CLEANED=$((R_CLEANED + 1))
    done < <(find "$OUTPUT_APP/src/main/java" -name "R\$*.java" -o -name "R.java")
fi
echo "  -> 清理了 $R_CLEANED 个反编译R.java"

# 删除080java中反编译的ijkplayer代码
IJK_PATH="$OUTPUT_APP/src/main/java/tv/danmaku/ijk"
if [ -d "$IJK_PATH" ]; then
    rm -rf "$IJK_PATH"
    echo "  -> 已删除反编译ijkplayer代码"
fi

# ============================================================================
# Phase 8: 修复 app/build.gradle
# ============================================================================
echo "[Phase 8/10] 修复 app/build.gradle..."

KU9_BUILD="$KU9_APP/build.gradle"
TVBOX_BUILD="$TVBOX_APP/build.gradle"
OUTPUT_BUILD="$OUTPUT_APP/build.gradle"

if [ -f "$TVBOX_BUILD" ]; then
    cp "$OUTPUT_BUILD" "$OUTPUT_BUILD.ku9.bak" 2>/dev/null || true
    cp "$TVBOX_BUILD" "$OUTPUT_BUILD"

    if [ -f "$KU9_BUILD" ]; then
        KU9_APPID=$(grep -oP "applicationId\s+'\K[^']+" "$KU9_BUILD" || echo "com.player.ku9py")
        KU9_VERSIONCODE=$(grep -oP "versionCode\s+\K[0-9]+" "$KU9_BUILD" || echo "1")
        KU9_VERSIONNAME=$(grep -oP "versionName\s+\"\K[^\"]+" "$KU9_BUILD" || echo "1.0.0")

        sed -i "s/applicationId .*/applicationId '$KU9_APPID'/" "$OUTPUT_BUILD"
        sed -i "s/versionCode .*/versionCode $KU9_VERSIONCODE/" "$OUTPUT_BUILD"
        sed -i "s/versionName .*/versionName \"$KU9_VERSIONNAME\"/" "$OUTPUT_BUILD"

        echo "  -> build.gradle 已修复: $KU9_APPID $KU9_VERSIONNAME ($KU9_VERSIONCODE)"
    fi
else
    echo "  [警告] 找不到TVBoxOS的app/build.gradle"
fi

# ============================================================================
# Phase 9: 保留酷9UI资源 + 补入TVBoxOS缺少的layout
# ============================================================================
echo "[Phase 9/10] 处理资源文件..."

mkdir -p "$OUTPUT_DIR/tvbox_layout_backup"
if [ -d "$TVBOX_APP/src/main/res/layout" ]; then
    cp -r "$TVBOX_APP/src/main/res/layout" "$OUTPUT_DIR/tvbox_layout_backup/"
fi

MISSING_LAYOUT=0
if [ -d "$TVBOX_APP/src/main/res/layout" ] && [ -d "$OUTPUT_APP/src/main/res/layout" ]; then
    while IFS= read -r layout_file; do
        layout_name=$(basename "$layout_file")
        if [ ! -f "$OUTPUT_APP/src/main/res/layout/$layout_name" ]; then
            cp "$layout_file" "$OUTPUT_APP/src/main/res/layout/$layout_name"
            MISSING_LAYOUT=$((MISSING_LAYOUT + 1))
        fi
    done < <(find "$TVBOX_APP/src/main/res/layout" -name "*.xml")
fi

if [ $MISSING_LAYOUT -gt 0 ]; then
    echo "  -> 补入了 $MISSING_LAYOUT 个TVBoxOS特有的layout"
fi

# ============================================================================
# Phase 10: 扫描酷9特有文件 + 生成报告
# ============================================================================
echo "[Phase 10/10] 生成报告..."

SPECIAL_FILE="$OUTPUT_DIR/KU9_SPECIAL_FILES.txt"
echo "# 酷9特有文件清单" > "$SPECIAL_FILE"
echo "" >> "$SPECIAL_FILE"

SPECIAL_COUNT=0
if [ -d "$KU9_JAVA" ] && [ -d "$TVBOX_JAVA" ]; then
    while IFS= read -r ku9_file; do
        rel_path="${ku9_file#$KU9_JAVA/}"
        if echo "$rel_path" | grep -qE "^R\$"; then continue; fi
        if [ "$rel_path" = "R.java" ]; then continue; fi
        tvbox_file="$TVBOX_JAVA/$rel_path"
        if [ ! -f "$tvbox_file" ]; then
            echo "$rel_path" >> "$SPECIAL_FILE"
            SPECIAL_COUNT=$((SPECIAL_COUNT + 1))
        fi
    done < <(find "$KU9_JAVA" -name "*.java" | sort)
fi

REPORT="$OUTPUT_DIR/MERGE_REPORT.md"
cat > "$REPORT" << EOF
# 酷9 + TVBoxOS + ijkplayer 合并报告

生成时间: $(date)

## 合并统计

| 项目 | 数量 |
|------|------|
| 替换的反编译文件 | $REPLACED |
| 新增的TVBoxOS功能 | $ADDED |
| 额外保留的Java文件 | $EXTRA_REPLACED |
| 清理的反编译R.java | $R_CLEANED |
| 补入的TVBoxOS layout | $MISSING_LAYOUT |
| 保留的酷9特有文件 | $SPECIAL_COUNT |

## 工程结构

- app/ - 酷9外壳 + TVBoxOS源码
- player/ - 播放器模块
- quickjs/ - QuickJS引擎
- pyramid/ - Python支持(Chaquopy)
- gradlew - 构建脚本

## 关键修复

1. **local.properties**: 已创建/复制，配置Android SDK路径
2. **pyramid模块**: 从TVBoxOS复制，需要local.properties中的sdk.dir
3. **build.gradle**: TVBoxOS依赖 + 酷9版本信息

## 编译命令

\`\`\`bash
cd $OUTPUT_DIR
chmod +x gradlew
./gradlew :app:assembleJavaDebug
\`\`\`

## 常见问题

**Q: pyramid模块报错**
A: pyramid使用Chaquopy(Python for Android)，需要local.properties中有sdk.dir。
   脚本已自动创建。如仍报错，检查ANDROID_SDK_ROOT环境变量。

**Q: 编译报错 "找不到符号 R.id.xxx"**
A: 酷9布局缺少TVBoxOS需要的View ID。从tvbox_layout_backup/中找到对应布局补全。

**Q: 编译报错 "找不到类 xxx"**
A: 酷9代码引用了被替换的类。检查该类是否在TVBoxOS中，如不在需从080java补入。
EOF

echo "  -> 报告已生成: $REPORT"

echo ""
echo "========================================"
echo "  合并完成！"
echo "========================================"
echo ""
echo "输出目录: $OUTPUT_DIR"
echo ""
echo "关键修复:"
echo "  - local.properties 已创建（pyramid模块需要）"
echo "  - 替换了 $REPLACED 个反编译文件"
echo "  - 新增了 $ADDED 个TVBoxOS功能文件"
echo "  - 保留了 $SPECIAL_COUNT 个酷9特有文件"
echo ""
echo "编译:"
echo "  cd $OUTPUT_DIR"
echo "  chmod +x gradlew"
echo "  ./gradlew :app:assembleJavaDebug"
echo ""
