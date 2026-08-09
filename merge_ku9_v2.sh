#!/bin/bash
# =============================================================================
# 最终版v2: 解决资源冲突 + 增强文件替换 + 清理损坏资源
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
echo "  酷9 + TVBoxOS + ijkplayer [v2]"
echo "========================================"
echo ""

if [ ! -d "$KU9_DIR" ]; then echo "[错误] 找不到 080java"; exit 1; fi
if [ ! -d "$TVBOX_DIR" ]; then echo "[错误] 找不到 TVBoxOS"; exit 1; fi

# ============================================================================
# Phase 1: 复制080java作为外壳基底
# ============================================================================
echo "[Phase 1/11] 复制080java作为外壳基底..."
rm -rf "$OUTPUT_DIR"
cp -r "$KU9_DIR" "$OUTPUT_DIR"

# ============================================================================
# Phase 2: 复制TVBoxOS构建系统
# ============================================================================
echo "[Phase 2/11] 复制TVBoxOS构建系统..."

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

# 创建local.properties（如不存在）
if [ ! -f "$OUTPUT_DIR/local.properties" ]; then
    SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    if [ -d "$SDK_DIR" ]; then
        echo "sdk.dir=$SDK_DIR" > "$OUTPUT_DIR/local.properties"
        echo "  -> local.properties 已创建"
    fi
fi

# ============================================================================
# Phase 3: 复制TVBoxOS子模块
# ============================================================================
echo "[Phase 3/11] 复制TVBoxOS子模块..."

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
echo "[Phase 4/11] 复制app的libs/jniLibs/assets..."

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
# Phase 5: 核心 - 用TVBoxOS源码替换080java反编译代码（增强版）
# ============================================================================
echo "[Phase 5/11] 核心: 替换反编译代码（增强版）..."

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
# Phase 6: 清理080java中所有反编译的R.java和标准库资源
# ============================================================================
echo "[Phase 6/11] 清理反编译产物和冲突资源..."

# 6.1 清理所有R.java
R_CLEANED=0
if [ -d "$OUTPUT_APP/src/main/java" ]; then
    while IFS= read -r rfile; do
        rm "$rfile"
        R_CLEANED=$((R_CLEANED + 1))
    done < <(find "$OUTPUT_APP/src/main/java" -name "R\$*.java" -o -name "R.java")
fi
echo "  -> 清理了 $R_CLEANED 个反编译R.java"

# 6.2 删除反编译的ijkplayer代码
IJK_PATH="$OUTPUT_APP/src/main/java/tv/danmaku/ijk"
if [ -d "$IJK_PATH" ]; then
    rm -rf "$IJK_PATH"
    echo "  -> 已删除反编译ijkplayer代码"
fi

# 6.3 【关键修复】删除080java中属于Android Support Library/AppCompat的冲突资源
# 这些资源不应该出现在项目res中，它们应该通过Gradle依赖引入
CONFLICT_RES=0

# 删除abc_前缀的drawable（AppCompat内部资源）
for d in drawable drawable-hdpi drawable-mdpi drawable-xhdpi drawable-xxhdpi drawable-xxxhdpi; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        while IFS= read -r f; do
            rm "$f"
            CONFLICT_RES=$((CONFLICT_RES + 1))
        done < <(find "$OUTPUT_APP/src/main/res/$d" -name "abc_*" -o -name "notification_*" 2>/dev/null || true)
    fi
done

# 删除design_前缀的资源（Material Design库内部资源）
for d in drawable drawable-hdpi drawable-mdpi drawable-xhdpi drawable-xxhdpi drawable-xxxhdpi layout; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        while IFS= read -r f; do
            rm "$f"
            CONFLICT_RES=$((CONFLICT_RES + 1))
        done < <(find "$OUTPUT_APP/src/main/res/$d" -name "design_*" 2>/dev/null || true)
    fi
done

# 删除mtrl_前缀的资源（Material Components内部资源）
for d in drawable drawable-hdpi drawable-mdpi drawable-xhdpi drawable-xxhdpi drawable-xxxhdpi layout color; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        while IFS= read -r f; do
            rm "$f"
            CONFLICT_RES=$((CONFLICT_RES + 1))
        done < <(find "$OUTPUT_APP/src/main/res/$d" -name "mtrl_*" 2>/dev/null || true)
    fi
done

# 删除values中的冲突文件（这些应该由依赖库提供）
for f in "attrs.xml" "attrs_private.xml" "colors_material.xml" "dimens_material.xml" "styles_material.xml" "themes_material.xml" "public.xml"; do
    if [ -f "$OUTPUT_APP/src/main/res/values/$f" ]; then
        rm "$OUTPUT_APP/src/main/res/values/$f"
        CONFLICT_RES=$((CONFLICT_RES + 1))
        echo "  -> 删除冲突values文件: $f"
    fi
done

# 删除values-night等目录中的冲突文件
for d in values-night values-v21 values-v23 values-v27 values-zh values-land values-sw600dp values-w820dp; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        for f in "attrs.xml" "styles.xml" "themes.xml" "colors.xml"; do
            if [ -f "$OUTPUT_APP/src/main/res/$d/$f" ]; then
                # 检查是否包含AppCompat/Support Library的重复定义
                if grep -q "navigationMode\|tintMode\|autoSizeTextType\|actionBarSize\|backgroundTintMode\|fontProviderFetchStrategy\|fontStyle\|keyPositionType\|motionDebug\|showDividers\|alphabeticModifiers\|buttonGravity\|autoTransition\|screenScaleType\|thumbTintMode\|buttonTintMode\|tickMarkTintMode" "$OUTPUT_APP/src/main/res/$d/$f" 2>/dev/null; then
                    rm "$OUTPUT_APP/src/main/res/$d/$f"
                    CONFLICT_RES=$((CONFLICT_RES + 1))
                    echo "  -> 删除冲突values文件: $d/$f"
                fi
            fi
        done
    fi
done

# 删除anim中的design/snackbar动画（Material库内部）
if [ -d "$OUTPUT_APP/src/main/res/anim" ]; then
    while IFS= read -r f; do
        rm "$f"
        CONFLICT_RES=$((CONFLICT_RES + 1))
    done < <(find "$OUTPUT_APP/src/main/res/anim" -name "design_*" -o -name "abc_*" 2>/dev/null || true)
fi

# 删除color中的mtrl/abc颜色（Material库内部）
if [ -d "$OUTPUT_APP/src/main/res/color" ]; then
    while IFS= read -r f; do
        rm "$f"
        CONFLICT_RES=$((CONFLICT_RES + 1))
    done < <(find "$OUTPUT_APP/src/main/res/color" -name "mtrl_*" -o -name "abc_*" -o -name "design_*" 2>/dev/null || true)
fi

if [ $CONFLICT_RES -gt 0 ]; then
    echo "  -> 删除了 $CONFLICT_RES 个冲突资源文件"
fi

# ============================================================================
# Phase 7: 处理values目录 - 用TVBoxOS的values替换080java的values（解决attr冲突）
# ============================================================================
echo "[Phase 7/11] 处理values目录..."

# 策略：保留080java的values，但删除其中会导致冲突的declare-styleable和attr
# 更好的策略：用TVBoxOS的values完全替换，但保留酷9特有的颜色/字符串

# 先备份080java的values
if [ -d "$OUTPUT_APP/src/main/res/values" ]; then
    cp -r "$OUTPUT_APP/src/main/res/values" "$OUTPUT_DIR/ku9_values_backup/"
fi

# 用TVBoxOS的values替换（TVBoxOS的values与AndroidX兼容）
if [ -d "$TVBOX_APP/src/main/res/values" ]; then
    rm -rf "$OUTPUT_APP/src/main/res/values"
    cp -r "$TVBOX_APP/src/main/res/values" "$OUTPUT_APP/src/main/res/values"
    echo "  -> values目录已用TVBoxOS版本替换（解决attr冲突）"
fi

# 从080java备份中恢复酷9特有的颜色/字符串（可选，如果需要酷9主题）
# 注意：只恢复colors.xml和strings.xml中TVBoxOS没有的定义
# 这里暂时不恢复，因为TVBoxOS的values已经包含了完整的主题配置

# 同样处理其他values目录
for d in values-night values-v21 values-v23 values-v27 values-zh; do
    if [ -d "$TVBOX_APP/src/main/res/$d" ]; then
        rm -rf "$OUTPUT_APP/src/main/res/$d"
        cp -r "$TVBOX_APP/src/main/res/$d" "$OUTPUT_APP/src/main/res/$d"
    fi
done

# ============================================================================
# Phase 8: 处理layout - 保留酷9的layout，补入TVBoxOS缺少的
# ============================================================================
echo "[Phase 8/11] 处理layout目录..."

# 备份TVBoxOS的layout
mkdir -p "$OUTPUT_DIR/tvbox_layout_backup"
if [ -d "$TVBOX_APP/src/main/res/layout" ]; then
    cp -r "$TVBOX_APP/src/main/res/layout" "$OUTPUT_DIR/tvbox_layout_backup/"
fi

# 保留080java的layout（酷9UI），但补入TVBoxOS特有的layout
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
# Phase 9: 修复 app/build.gradle
# ============================================================================
echo "[Phase 9/11] 修复 app/build.gradle..."

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
# Phase 10: 处理ijkplayer
# ============================================================================
echo "[Phase 10/11] 处理ijkplayer..."

if [ -n "$IJKPLAYER_DIR" ] && [ -d "$IJKPLAYER_DIR" ] && [ -d "$OUTPUT_DIR/player" ]; then
    echo "  -> 用官方ijkplayer源码替换..."
    PLAYER_IJK="$OUTPUT_DIR/player/src/main/java/tv/danmaku/ijk"
    if [ -d "$PLAYER_IJK" ]; then
        rm -rf "$PLAYER_IJK"
    fi
    IJK_JAVA="$IJKPLAYER_DIR/ijkplayer-java/src/main/java/tv/danmaku/ijk"
    if [ -d "$IJK_JAVA" ]; then
        mkdir -p "$PLAYER_IJK"
        cp -r "$IJK_JAVA/"* "$PLAYER_IJK/"
    fi
    IJK_JNILIBS="$IJKPLAYER_DIR/ijkplayer-java/src/main/jniLibs"
    if [ -d "$IJK_JNILIBS" ]; then
        mkdir -p "$OUTPUT_DIR/player/src/main/jniLibs"
        cp -r "$IJK_JNILIBS/"* "$OUTPUT_DIR/player/src/main/jniLibs/"
    fi
    echo "  -> ijkplayer已用官方源码替换"
else
    echo "  -> 使用TVBoxOS内置ijkplayer"
fi

# ============================================================================
# Phase 11: 扫描酷9特有文件 + 生成报告
# ============================================================================
echo "[Phase 11/11] 生成报告..."

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
# 酷9 + TVBoxOS + ijkplayer 合并报告 v2

生成时间: $(date)

## 修复内容

### 1. 资源冲突解决
- 删除了 $CONFLICT_RES 个冲突资源文件（AppCompat/Material Design内部资源）
- 用TVBoxOS的values目录完全替换080java的values（解决attr重复定义）
- 删除了损坏的PNG文件（abc_list_divider_mtrl_alpha.9.png等）

### 2. 布局保留
- 保留080java的layout/（酷9UI风格）
- 补入 $MISSING_LAYOUT 个TVBoxOS特有的layout

## 合并统计

| 项目 | 数量 |
|------|------|
| 替换的Java文件 | $REPLACED |
| 新增的Java文件 | $ADDED |
| 清理的反编译R.java | $R_CLEANED |
| 删除的冲突资源 | $CONFLICT_RES |
| 补入的layout | $MISSING_LAYOUT |
| 保留的酷9特有文件 | $SPECIAL_COUNT |

## 编译命令

\`\`\`bash
cd $OUTPUT_DIR
chmod +x gradlew
./gradlew :app:assembleJavaDebug
\`\`\`

## 如仍报错

**"找不到符号 R.id.xxx"** -> layout中缺少View ID，从tvbox_layout_backup/复制
**"找不到类 xxx"** -> 酷9代码引用被替换的类，检查并修复
**"方法签名不匹配"** -> 酷9调用TVBoxOS中已更改的方法
EOF

echo "  -> 报告已生成"

echo ""
echo "========================================"
echo "  合并完成！"
echo "========================================"
echo ""
echo "关键修复:"
echo "  - 删除了 $CONFLICT_RES 个冲突资源（解决attr重复定义）"
echo "  - values目录已用TVBoxOS版本替换"
echo "  - 清理了损坏的PNG文件"
echo ""
echo "编译:"
echo "  cd $OUTPUT_DIR"
echo "  chmod +x gradlew"
echo "  ./gradlew :app:assembleJavaDebug"
echo ""
