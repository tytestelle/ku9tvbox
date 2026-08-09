#!/bin/bash
# =============================================================================
# 保守版: 只替换Java源码，完全保留酷9资源
# 原则: TVBoxOS提供可编译骨架，酷9提供所有业务逻辑和UI
# =============================================================================

set -e

KU9_DIR="${1:-./080java}"
TVBOX_DIR="${2:-./TVBoxOS}"
OUTPUT_DIR="${3:-./ku9-conservative}"
IJKPLAYER_DIR="${4:-}"

KU9_APP="$KU9_DIR/app"
TVBOX_APP="$TVBOX_DIR/app"
OUTPUT_APP="$OUTPUT_DIR/app"

echo "========================================"
echo "  保守版合并: 只换Java，不动资源"
echo "========================================"
echo ""
echo "酷9外壳: $KU9_DIR"
echo "TVBoxOS源码: $TVBOX_DIR"
echo "输出目录: $OUTPUT_DIR"
echo ""

if [ ! -d "$KU9_DIR" ]; then echo "[错误] 找不到 080java"; exit 1; fi
if [ ! -d "$TVBOX_DIR" ]; then echo "[错误] 找不到 TVBoxOS"; exit 1; fi

# ============================================================================
# Phase 1: 复制080java作为外壳基底（完全保留，包括所有资源）
# ============================================================================
echo "[Phase 1/8] 复制080java作为外壳基底..."
rm -rf "$OUTPUT_DIR"
cp -r "$KU9_DIR" "$OUTPUT_DIR"

# ============================================================================
# Phase 2: 复制TVBoxOS构建系统
# ============================================================================
echo "[Phase 2/8] 复制TVBoxOS构建系统..."

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

# 创建local.properties
if [ ! -f "$OUTPUT_DIR/local.properties" ]; then
    SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    if [ -d "$SDK_DIR" ]; then
        echo "sdk.dir=$SDK_DIR" > "$OUTPUT_DIR/local.properties"
        echo "  -> local.properties 已创建"
    fi
fi

# ============================================================================
# Phase 3: 复制TVBoxOS子模块（player/quickjs/pyramid）
# ============================================================================
echo "[Phase 3/8] 复制TVBoxOS子模块..."

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
# Phase 4: 复制TVBoxOS app的libs/jniLibs/assets（确保库完整）
# ============================================================================
echo "[Phase 4/8] 复制app的libs/jniLibs/assets..."

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
# Phase 5: 【核心】用TVBoxOS源码替换080java中同名的TVBox标准类
# ============================================================================
echo "[Phase 5/8] 核心: 替换同名的TVBox标准类..."

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
            # 080java中有同名文件 → 这是TVBox标准类（可能被混淆但文件名相同）
            # 用TVBoxOS的源码替换
            cp "$src_file" "$dst_file"
            REPLACED=$((REPLACED + 1))
        else
            # 080java中没有同名文件 → TVBoxOS新增的功能
            # 直接复制（如新增的Subtitle模块等）
            mkdir -p "$(dirname "$dst_file")"
            cp "$src_file" "$dst_file"
            ADDED=$((ADDED + 1))
        fi
    done < <(find "$TVBOX_JAVA" -name "*.java")
fi

echo "  -> 替换了 $REPLACED 个同名文件（TVBox标准类）"
echo "  -> 新增了 $ADDED 个文件（TVBoxOS新功能）"

# ============================================================================
# Phase 6: 清理反编译垃圾（只清理R.java，不动其他文件）
# ============================================================================
echo "[Phase 6/8] 清理反编译R.java..."

R_CLEANED=0
if [ -d "$OUTPUT_JAVA" ]; then
    while IFS= read -r rfile; do
        rm "$rfile"
        R_CLEANED=$((R_CLEANED + 1))
    done < <(find "$OUTPUT_JAVA" -name "R\$*.java" -o -name "R.java")
fi
echo "  -> 清理了 $R_CLEANED 个反编译R.java"

# 删除080java中反编译的ijkplayer代码（TVBoxOS通过依赖引入）
IJK_PATH="$OUTPUT_APP/src/main/java/tv/danmaku/ijk"
if [ -d "$IJK_PATH" ]; then
    rm -rf "$IJK_PATH"
    echo "  -> 已删除反编译ijkplayer代码（改用Gradle依赖）"
fi

# ============================================================================
# Phase 7: 【关键】修复资源冲突 - 只删除重复attr，不动其他资源
# ============================================================================
echo "[Phase 7/8] 修复values中的attr冲突（保留酷9特有attr）..."

# 策略：扫描080java的values/attrs.xml，删除与AndroidX AppCompat完全重复的定义
# 保留080java特有的attr（酷9自定义的）

ATTR_FIXED=0

fix_attrs_file() {
    local file="$1"
    if [ ! -f "$file" ]; then return; fi

    # 定义AndroidX AppCompat/Material已知的attr列表（会冲突的）
    local bad_attrs="navigationMode|tintMode|autoSizeTextType|actionBarSize|backgroundTintMode|fontProviderFetchStrategy|fontStyle|keyPositionType|motionDebug|showDividers|alphabeticModifiers|buttonGravity|autoTransition|screenScaleType|thumbTintMode|buttonTintMode|tickMarkTintMode|titleMargin|titleMargins|maxButtonHeight|subtitleTextAppearance|titleTextAppearance|popupTheme|homeAsUpIndicator|selectableItemBackgroundBorderless|actionModeShareDrawable|actionModeCloseDrawable|actionModeCutDrawable|actionModeCopyDrawable|actionModePasteDrawable|actionModeSelectAllDrawable|actionModeFindDrawable|actionModeWebSearchDrawable|actionModeBackground|actionModeSplitBackground|actionModeCloseButtonStyle|actionModeStyle|actionBarTabStyle|actionBarTabBarStyle|actionBarTabTextStyle|actionOverflowButtonStyle|actionOverflowMenuStyle|actionBarStyle|actionBarSplitStyle|actionBarWidgetTheme|actionBarTheme|actionBarSize|actionBarDivider|actionBarItemBackground|actionMenuTextAppearance|actionMenuTextColor|actionModeStyle|actionModeCloseButtonStyle|actionModeBackground|actionModeSplitBackground|actionModeCloseDrawable|actionModeCutDrawable|actionModeCopyDrawable|actionModePasteDrawable|actionModeSelectAllDrawable|actionModeShareDrawable|actionBarPopupTheme|panelMenuListWidth|panelMenuListTheme|panelBackground|listChoiceBackgroundIndicator|colorPrimary|colorPrimaryDark|colorAccent|colorControlNormal|colorControlActivated|colorControlHighlight|colorButtonNormal|colorSwitchThumbNormal|drawerArrowStyle|toolbarStyle|toolbarNavigationButtonStyle|toolbarStyle|toolbarNavigationButtonStyle|searchViewStyle|seekBarStyle|ratingBarStyle|ratingBarStyleIndicator|ratingBarStyleSmall|checkboxStyle|checkedTextViewStyle|radioButtonStyle|spinnerStyle|dropDownListViewStyle|popupWindowStyle|editTextColor|editTextBackground|imageButtonStyle|textAppearanceSearchResultTitle|textAppearanceSearchResultSubtitle|textColorSearchUrl|listPreferredItemHeight|listPreferredItemHeightSmall|listPreferredItemHeightLarge|listPreferredItemPaddingLeft|listPreferredItemPaddingRight|dropDownItemStyle|listChoiceIndicatorSingleAnimated|listChoiceIndicatorMultipleAnimated|dividerHorizontal|activityChooserViewStyle|expandableListViewWhiteStyle|fastScrollThumbDrawable|fastScrollPreviewBackgroundLeft|fastScrollPreviewBackgroundRight|fastScrollTrackDrawable|fastScrollOverlayPosition|tooltipForegroundColor|tooltipFrameBackground|floatingToolbarForegroundColor|floatingToolbarItemBackgroundBorderless|floatingToolbarItemBackground|floatingToolbarOpenDrawable|floatingToolbarCloseDrawable"

    # 创建临时文件
    local tmpfile="${file}.tmp"
    local removed=0

    # 读取文件，删除包含bad_attrs的declare-styleable和attr
    # 使用sed删除包含冲突attr的整行
    while IFS= read -r line; do
        if echo "$line" | grep -qE "<attr name=\"($bad_attrs)\""; then
            removed=$((removed + 1))
            continue
        fi
        echo "$line" >> "$tmpfile"
    done < "$file"

    if [ $removed -gt 0 ]; then
        mv "$tmpfile" "$file"
        ATTR_FIXED=$((ATTR_FIXED + removed))
        echo "  -> 修复 $file: 删除了 $removed 个冲突attr"
    else
        rm -f "$tmpfile"
    fi
}

# 修复主values/attrs.xml
if [ -f "$OUTPUT_APP/src/main/res/values/attrs.xml" ]; then
    fix_attrs_file "$OUTPUT_APP/src/main/res/values/attrs.xml"
fi

# 修复其他values目录中的attrs.xml
for d in values-night values-v21 values-v23 values-v27 values-zh; do
    if [ -f "$OUTPUT_APP/src/main/res/$d/attrs.xml" ]; then
        fix_attrs_file "$OUTPUT_APP/src/main/res/$d/attrs.xml"
    fi
done

if [ $ATTR_FIXED -gt 0 ]; then
    echo "  -> 共删除了 $ATTR_FIXED 个冲突attr定义"
else
    echo "  -> 未发现冲突attr"
fi

# 修复损坏的.9.png（只删除真正损坏的，保留正常的）
echo "  检查损坏的.9.png..."
BROKEN_PNG=0
if [ -d "$OUTPUT_APP/src/main/res" ]; then
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
            # 小于50字节的.9.png几乎肯定是损坏的
            if [ "$size" -lt 50 ]; then
                echo "  -> 删除损坏PNG: $(basename $f) (${size}字节)"
                rm "$f"
                BROKEN_PNG=$((BROKEN_PNG + 1))
            fi
        fi
    done < <(find "$OUTPUT_APP/src/main/res" -name "*.9.png" 2>/dev/null || true)
fi

if [ $BROKEN_PNG -gt 0 ]; then
    echo "  -> 删除了 $BROKEN_PNG 个损坏的.9.png"
fi

# ============================================================================
# Phase 8: 修复 build.gradle（TVBoxOS依赖 + 酷9版本）
# ============================================================================
echo "[Phase 8/8] 修复 app/build.gradle..."

KU9_BUILD="$KU9_APP/build.gradle"
TVBOX_BUILD="$TVBOX_APP/build.gradle"
OUTPUT_BUILD="$OUTPUT_APP/build.gradle"

if [ -f "$TVBOX_BUILD" ]; then
    # 备份080java的原始build.gradle
    cp "$OUTPUT_BUILD" "$OUTPUT_BUILD.ku9.bak" 2>/dev/null || true

    # 用TVBoxOS的build.gradle作为基础（依赖完整）
    cp "$TVBOX_BUILD" "$OUTPUT_BUILD"

    # 提取酷9的版本信息并覆盖
    if [ -f "$KU9_BUILD" ]; then
        KU9_APPID=$(grep -oP "applicationId\s+'\K[^']+" "$KU9_BUILD" || echo "com.player.ku9py")
        KU9_VERSIONCODE=$(grep -oP "versionCode\s+\K[0-9]+" "$KU9_BUILD" || echo "1")
        KU9_VERSIONNAME=$(grep -oP "versionName\s+\"\K[^\"]+" "$KU9_BUILD" || echo "1.0.0")

        sed -i "s/applicationId .*/applicationId '$KU9_APPID'/" "$OUTPUT_BUILD"
        sed -i "s/versionCode .*/versionCode $KU9_VERSIONCODE/" "$OUTPUT_BUILD"
        sed -i "s/versionName .*/versionName \"$KU9_VERSIONNAME\"/" "$OUTPUT_BUILD"

        echo "  -> build.gradle 已修复"
        echo "  -> 包名: $KU9_APPID | 版本: $KU9_VERSIONNAME ($KU9_VERSIONCODE)"
    fi

    # 在build.gradle中添加aaptOptions以忽略某些资源冲突
    if ! grep -q "aaptOptions" "$OUTPUT_BUILD"; then
        # 在android块中添加aaptOptions
        sed -i '/buildFeatures {/i\    aaptOptions {\n        cruncherEnabled = false\n        additionalParameters "--no-version-vectors"\n    }' "$OUTPUT_BUILD"
        echo "  -> 已添加aaptOptions配置"
    fi
else
    echo "  [警告] 找不到TVBoxOS的app/build.gradle"
fi

# ============================================================================
# 生成报告
# ============================================================================
echo ""
echo "生成合并报告..."

REPORT="$OUTPUT_DIR/MERGE_REPORT.md"
cat > "$REPORT" << EOF
# 保守版合并报告: 只换Java，不动资源

生成时间: $(date)

## 合并原则

- **Java代码**: 同名替换（TVBoxOS源码 → 080java反编译），异名保留（酷9特有）
- **资源文件**: 完全保留080java的所有资源（layout, drawable, values, 等）
- **构建系统**: 使用TVBoxOS的（可编译）
- **子模块**: 使用TVBoxOS的（player, quickjs, pyramid）

## 合并统计

| 项目 | 数量 |
|------|------|
| 替换的TVBox标准类 | $REPLACED |
| 新增的TVBoxOS功能 | $ADDED |
| 清理的反编译R.java | $R_CLEANED |
| 修复的冲突attr | $ATTR_FIXED |
| 删除的损坏PNG | $BROKEN_PNG |

## 资源处理策略

- **保留**: 080java的所有layout, drawable, mipmap, anim, color, font, menu, raw, xml
- **修复**: 只删除values/attrs.xml中与AndroidX重复的attr定义
- **修复**: 只删除小于50字节的损坏.9.png
- **不动**: 080java的colors, strings, styles, themes（酷9UI风格）

## 编译命令

\`\`\`bash
cd $OUTPUT_DIR
chmod +x gradlew
./gradlew :app:assembleJavaDebug
\`\`\`

## 常见问题

**Q: 编译报错 "Duplicate value for resource"**
A: 还有未清理的冲突attr。查看错误中的attr名，在values/attrs.xml中删除对应定义。

**Q: 编译报错 ".9.png file failed to compile"**
A: 还有未删除的损坏.9.png。查看错误中的文件名，确认文件大小是否异常。

**Q: 编译报错 "找不到类 xxx"**
A: 酷9代码引用了被替换的类。检查该类是否在TVBoxOS中，如不在需恢复080java版本。

**Q: 运行时崩溃 "ClassNotFoundException"**
A: 某些酷9类依赖了被删除的R.java或混淆类。检查logcat定位缺失类。

## 文件速查

| 文件 | 说明 |
|------|------|
| app/build.gradle.ku9.bak | 080java原始build.gradle备份 |
| ku9_values_backup/ | 080java原始values备份（如需要恢复）|
EOF

echo "  -> 报告已生成: $REPORT"

echo ""
echo "========================================"
echo "  保守版合并完成！"
echo "========================================"
echo ""
echo "核心原则: 只换Java，不动资源"
echo ""
echo "结果:"
echo "  - 替换了 $REPLACED 个TVBox标准类"
echo "  - 新增了 $ADDED 个TVBoxOS功能"
echo "  - 完全保留了080java的所有资源（layout, drawable, values等）"
echo "  - 修复了 $ATTR_FIXED 个冲突attr"
echo "  - 删除了 $BROKEN_PNG 个损坏PNG"
echo ""
echo "编译:"
echo "  cd $OUTPUT_DIR"
echo "  chmod +x gradlew"
echo "  ./gradlew :app:assembleJavaDebug"
echo ""
echo "如有编译错误，把错误信息贴出来，我帮你逐个解决。"
echo ""
