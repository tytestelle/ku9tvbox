#!/bin/bash
# =============================================================================
# v3: 彻底清理所有第三方库内部资源 + 损坏PNG
# 新增: lb_*(Leanback), avd_*, btn_*, ic_*(部分), dialog_*, menu_*, rate_*, tooltip_*
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
echo "  酷9 + TVBoxOS + ijkplayer [v3]"
echo "========================================"
echo ""

if [ ! -d "$KU9_DIR" ]; then echo "[错误] 找不到 080java"; exit 1; fi
if [ ! -d "$TVBOX_DIR" ]; then echo "[错误] 找不到 TVBoxOS"; exit 1; fi

# ============================================================================
# Phase 1-5: 与v2相同（复制基底、构建系统、子模块、libs、替换Java）
# ============================================================================
echo "[Phase 1/12] 复制080java作为外壳基底..."
rm -rf "$OUTPUT_DIR"
cp -r "$KU9_DIR" "$OUTPUT_DIR"

echo "[Phase 2/12] 复制TVBoxOS构建系统..."
for item in gradlew gradle settings.gradle gradle.properties build.gradle local.properties; do
    src="$TVBOX_DIR/$item"
    dst="$OUTPUT_DIR/$item"
    if [ -e "$src" ]; then
        if [ -d "$src" ]; then rm -rf "$dst"; cp -r "$src" "$dst"; else cp "$src" "$dst"; fi
        echo "  -> $item 已复制"
    fi
done
chmod +x "$OUTPUT_DIR/gradlew" 2>/dev/null || true

if [ ! -f "$OUTPUT_DIR/local.properties" ]; then
    SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    if [ -d "$SDK_DIR" ]; then
        echo "sdk.dir=$SDK_DIR" > "$OUTPUT_DIR/local.properties"
        echo "  -> local.properties 已创建"
    fi
fi

echo "[Phase 3/12] 复制TVBoxOS子模块..."
for module in "$TVBOX_DIR"/*; do
    module_name=$(basename "$module")
    if [ ! -d "$module" ] || [ "$module_name" = "app" ]; then continue; fi
    if echo "$module_name" | grep -qE "^\.|\.git|\.github|docs|README|LICENSE"; then continue; fi
    if [ -f "$module/build.gradle" ]; then
        dst="$OUTPUT_DIR/$module_name"
        rm -rf "$dst"
        cp -r "$module" "$dst"
        echo "  -> 模块 $module_name 已复制"
    fi
done

echo "[Phase 4/12] 复制app的libs/jniLibs/assets..."
for dir in libs "src/main/jniLibs" "src/main/assets"; do
    src="$TVBOX_APP/$dir"
    dst="$OUTPUT_APP/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -r "$src/"* "$dst/" 2>/dev/null || true
        echo "  -> app/$dir 已复制"
    fi
done

echo "[Phase 5/12] 核心: 替换反编译代码..."
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
# Phase 6: 【v3增强】彻底清理所有第三方库内部资源
# ============================================================================
echo "[Phase 6/12] 彻底清理第三方库内部资源和损坏文件..."

# 6.1 清理R.java
R_CLEANED=0
if [ -d "$OUTPUT_APP/src/main/java" ]; then
    while IFS= read -r rfile; do
        rm "$rfile"
        R_CLEANED=$((R_CLEANED + 1))
    done < <(find "$OUTPUT_APP/src/main/java" -name "R\$*.java" -o -name "R.java")
fi
echo "  -> 清理了 $R_CLEANED 个反编译R.java"

# 6.2 删除反编译ijkplayer
IJK_PATH="$OUTPUT_APP/src/main/java/tv/danmaku/ijk"
if [ -d "$IJK_PATH" ]; then
    rm -rf "$IJK_PATH"
    echo "  -> 已删除反编译ijkplayer代码"
fi

# 6.3 【v3关键增强】删除所有第三方库的内部资源
# 这些资源前缀来自: AppCompat, Material Design, Leanback, ExoPlayer, 等
CONFLICT_RES=0

# 定义所有需要删除的资源前缀模式
BAD_PREFIXES=(
    "abc_*"           # AppCompat
    "design_*"        # Material Design
    "mtrl_*"          # Material Components
    "notification_*"  # Support Library通知
    "lb_*"            # Leanback (Android TV)
    "avd_*"           # AnimatedVectorDrawable
    "exo_*"           # ExoPlayer (部分内部资源)
    "exo2_*"          # ExoPlayer
    "ic_media_*"      # MediaRouter
    "mr_*"            # MediaRouter
    "cast_*"          # Cast
    "places_*"        # Places
    "common_*"        # Google Play Services
    "googleg_*"       # Google
    "quantum_*"       # Material
    "card_*"          # CardView
    "recycler_*"      # RecyclerView
    "preference_*"    # Preference
    "switch_*"        # SwitchCompat
    "text_select_*"   # Text Selection
    "autofill_*"      # Autofill
    "emoji_*"         # Emoji
    "fastscroll_*"    # FastScroller
    "ic_*"            # 部分系统图标(需谨慎)
    "btn_*"           # 按钮资源
    "dialog_*"        # 对话框背景
    "menu_*"          # 菜单资源
    "rate_*"          # 评分
    "tooltip_*"       # 提示
    "test_*"          # 测试
    "watch_*"         # Wear
)

# 在drawable各密度目录中删除
for d in drawable drawable-ldpi drawable-mdpi drawable-hdpi drawable-xhdpi drawable-xxhdpi drawable-xxxhdpi drawable-v21 drawable-v24 drawable-night drawable-ldrtl; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        for pattern in "${BAD_PREFIXES[@]}"; do
            while IFS= read -r f; do
                if [ -f "$f" ]; then
                    rm "$f"
                    CONFLICT_RES=$((CONFLICT_RES + 1))
                fi
            done < <(find "$OUTPUT_APP/src/main/res/$d" -name "$pattern" 2>/dev/null || true)
        done
    fi
done

# 删除anim中的冲突动画
if [ -d "$OUTPUT_APP/src/main/res/anim" ]; then
    for pattern in "design_*" "abc_*" "btn_*" "tooltip_*" "recycler_*"; do
        while IFS= read -r f; do
            if [ -f "$f" ]; then
                rm "$f"
                CONFLICT_RES=$((CONFLICT_RES + 1))
            fi
        done < <(find "$OUTPUT_APP/src/main/res/anim" -name "$pattern" 2>/dev/null || true)
    done
fi

# 删除color中的冲突颜色
if [ -d "$OUTPUT_APP/src/main/res/color" ]; then
    for pattern in "abc_*" "mtrl_*" "design_*" "switch_*" "btn_*"; do
        while IFS= read -r f; do
            if [ -f "$f" ]; then
                rm "$f"
                CONFLICT_RES=$((CONFLICT_RES + 1))
            fi
        done < <(find "$OUTPUT_APP/src/main/res/color" -name "$pattern" 2>/dev/null || true)
    done
fi

# 删除values中的冲突文件
for f in "attrs.xml" "attrs_private.xml" "colors_material.xml" "dimens_material.xml" "styles_material.xml" "themes_material.xml" "public.xml" "ids.xml" "integers.xml" "bools.xml" "strings.xml"; do
    if [ -f "$OUTPUT_APP/src/main/res/values/$f" ]; then
        # 检查是否包含第三方库的重复定义
        if grep -qE "navigationMode|tintMode|autoSizeTextType|actionBarSize|backgroundTintMode|fontProviderFetchStrategy|fontStyle|keyPositionType|motionDebug|showDividers|alphabeticModifiers|buttonGravity|autoTransition|screenScaleType|thumbTintMode|buttonTintMode|tickMarkTintMode|lb_|exo_|mtrl_|abc_|design_|avd_|cast_|mr_|ic_media_" "$OUTPUT_APP/src/main/res/values/$f" 2>/dev/null; then
            rm "$OUTPUT_APP/src/main/res/values/$f"
            CONFLICT_RES=$((CONFLICT_RES + 1))
            echo "  -> 删除冲突values文件: $f"
        fi
    fi
done

# 删除values-night等目录中的冲突文件
for d in values-night values-v21 values-v23 values-v27 values-zh values-land values-sw600dp values-w820dp values-xlarge values-v16 values-v17 values-v19; do
    if [ -d "$OUTPUT_APP/src/main/res/$d" ]; then
        for f in "attrs.xml" "styles.xml" "themes.xml" "colors.xml" "dimens.xml" "strings.xml"; do
            if [ -f "$OUTPUT_APP/src/main/res/$d/$f" ]; then
                if grep -qE "lb_|exo_|mtrl_|abc_|design_|avd_|cast_|mr_|ic_media_|navigationMode|tintMode|autoSizeTextType|actionBarSize" "$OUTPUT_APP/src/main/res/$d/$f" 2>/dev/null; then
                    rm "$OUTPUT_APP/src/main/res/$d/$f"
                    CONFLICT_RES=$((CONFLICT_RES + 1))
                    echo "  -> 删除冲突values文件: $d/$f"
                fi
            fi
        done
    fi
done

# 删除损坏的.9.png文件（文件大小异常小的）
BROKEN_9PNG=0
if [ -d "$OUTPUT_APP/src/main/res" ]; then
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
            # 小于100字节的.9.png通常是损坏的
            if [ "$size" -lt 100 ]; then
                rm "$f"
                BROKEN_9PNG=$((BROKEN_9PNG + 1))
            fi
        fi
    done < <(find "$OUTPUT_APP/src/main/res" -name "*.9.png" 2>/dev/null || true)
fi

if [ $BROKEN_9PNG -gt 0 ]; then
    echo "  -> 删除了 $BROKEN_9PNG 个损坏的.9.png文件"
fi

if [ $CONFLICT_RES -gt 0 ]; then
    echo "  -> 共删除了 $CONFLICT_RES 个冲突资源文件"
fi

# ============================================================================
# Phase 7: 处理values目录
# ============================================================================
echo "[Phase 7/12] 处理values目录..."

if [ -d "$OUTPUT_APP/src/main/res/values" ]; then
    cp -r "$OUTPUT_APP/src/main/res/values" "$OUTPUT_DIR/ku9_values_backup/"
fi

if [ -d "$TVBOX_APP/src/main/res/values" ]; then
    rm -rf "$OUTPUT_APP/src/main/res/values"
    cp -r "$TVBOX_APP/src/main/res/values" "$OUTPUT_APP/src/main/res/values"
    echo "  -> values目录已用TVBoxOS版本替换"
fi

for d in values-night values-v21 values-v23 values-v27 values-zh; do
    if [ -d "$TVBOX_APP/src/main/res/$d" ]; then
        rm -rf "$OUTPUT_APP/src/main/res/$d"
        cp -r "$TVBOX_APP/src/main/res/$d" "$OUTPUT_APP/src/main/res/$d"
    fi
done

# ============================================================================
# Phase 8: 处理layout
# ============================================================================
echo "[Phase 8/12] 处理layout目录..."

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
# Phase 9: 修复 build.gradle
# ============================================================================
echo "[Phase 9/12] 修复 app/build.gradle..."

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
fi

# ============================================================================
# Phase 10: 处理ijkplayer
# ============================================================================
echo "[Phase 10/12] 处理ijkplayer..."

if [ -n "$IJKPLAYER_DIR" ] && [ -d "$IJKPLAYER_DIR" ] && [ -d "$OUTPUT_DIR/player" ]; then
    echo "  -> 用官方ijkplayer源码替换..."
    PLAYER_IJK="$OUTPUT_DIR/player/src/main/java/tv/danmaku/ijk"
    if [ -d "$PLAYER_IJK" ]; then rm -rf "$PLAYER_IJK"; fi
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
# Phase 11: 扫描酷9特有文件
# ============================================================================
echo "[Phase 11/12] 扫描酷9特有文件..."

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

echo "  -> 保留了 $SPECIAL_COUNT 个酷9特有文件"

# ============================================================================
# Phase 12: 生成报告
# ============================================================================
echo "[Phase 12/12] 生成报告..."

REPORT="$OUTPUT_DIR/MERGE_REPORT.md"
cat > "$REPORT" << EOF
# 酷9 + TVBoxOS + ijkplayer 合并报告 v3

生成时间: $(date)

## v3 关键修复

### 彻底清理第三方库内部资源
删除了以下前缀的资源文件，避免与Gradle依赖库冲突：
- abc_* (AppCompat)
- design_* (Material Design)
- mtrl_* (Material Components)
- notification_* (Support Library)
- lb_* (Leanback/Android TV) ← 修复了上次编译错误
- avd_* (AnimatedVectorDrawable)
- exo_* (ExoPlayer)
- mr_*, ic_media_* (MediaRouter)
- cast_* (Cast)
- 以及 btn_*, dialog_*, menu_*, rate_*, tooltip_* 等

### 删除损坏的.9.png
删除了小于100字节的损坏.9.png文件

## 合并统计

| 项目 | 数量 |
|------|------|
| 替换的Java文件 | $REPLACED |
| 新增的Java文件 | $ADDED |
| 清理的反编译R.java | $R_CLEANED |
| 删除的冲突资源 | $CONFLICT_RES |
| 删除的损坏.9.png | $BROKEN_9PNG |
| 补入的layout | $MISSING_LAYOUT |
| 保留的酷9文件 | $SPECIAL_COUNT |

## 编译命令

\`\`\`bash
cd $OUTPUT_DIR
chmod +x gradlew
./gradlew :app:assembleJavaDebug
\`\`\`
EOF

echo "  -> 报告已生成"

echo ""
echo "========================================"
echo "  合并完成！"
echo "========================================"
echo ""
echo "v3 关键修复:"
echo "  - 彻底清理了所有第三方库内部资源（含lb_* Leanback资源）"
echo "  - 删除了损坏的.9.png文件"
echo ""
echo "编译:"
echo "  cd $OUTPUT_DIR"
echo "  chmod +x gradlew"
echo "  ./gradlew :app:assembleJavaDebug"
echo ""
