#!/bin/bash
# =============================================================================
# 最终版合并脚本: 酷9外壳 + TVBoxOS完整源码 + 官方ijkplayer
# 
# 用法: ./merge_ku9_final.sh <080java路径> <TVBoxOS路径> <输出路径> [ijkplayer路径]
# 示例: ./merge_ku9_final.sh ./080java ./TVBoxOS ./ku9-final
#       ./merge_ku9_final.sh ./080java ./TVBoxOS ./ku9-final ./ijkplayer
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
echo "  酷9外壳 + TVBoxOS源码 + ijkplayer"
echo "========================================"
echo ""
echo "酷9外壳: $KU9_DIR"
echo "TVBoxOS源码: $TVBOX_DIR"
echo "输出目录: $OUTPUT_DIR"
if [ -n "$IJKPLAYER_DIR" ]; then
    echo "ijkplayer官方源码: $IJKPLAYER_DIR"
fi
echo ""

# 验证输入
if [ ! -d "$KU9_DIR" ]; then echo "[错误] 找不到 080java: $KU9_DIR"; exit 1; fi
if [ ! -d "$TVBOX_DIR" ]; then echo "[错误] 找不到 TVBoxOS: $TVBOX_DIR"; exit 1; fi
if [ -n "$IJKPLAYER_DIR" ] && [ ! -d "$IJKPLAYER_DIR" ]; then
    echo "[警告] 找不到 ijkplayer 目录: $IJKPLAYER_DIR"
    IJKPLAYER_DIR=""
fi

# ============================================================================
# Phase 1: 复制080java作为外壳基底
# ============================================================================
echo "[Phase 1/9] 复制080java作为外壳基底..."
rm -rf "$OUTPUT_DIR"
cp -r "$KU9_DIR" "$OUTPUT_DIR"

# ============================================================================
# Phase 2: 复制TVBoxOS的完整构建系统
# ============================================================================
echo "[Phase 2/9] 复制TVBoxOS构建系统..."

# 复制根目录构建文件
for item in gradlew gradle settings.gradle gradle.properties build.gradle; do
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

# ============================================================================
# Phase 3: 复制TVBoxOS的子模块（player, quickjs, pyramid等）
# ============================================================================
echo "[Phase 3/9] 复制TVBoxOS子模块..."

# 扫描TVBoxOS根目录下的所有子模块（除了app）
for module in "$TVBOX_DIR"/*; do
    module_name=$(basename "$module")
    # 跳过非目录项和app目录
    if [ ! -d "$module" ] || [ "$module_name" = "app" ]; then
        continue
    fi
    # 跳过隐藏目录和常见非模块目录
    if echo "$module_name" | grep -qE "^\.|\.git|\.github|docs|README|LICENSE"; then
        continue
    fi
    # 检查是否有build.gradle（确认是Gradle模块）
    if [ -f "$module/build.gradle" ]; then
        dst="$OUTPUT_DIR/$module_name"
        rm -rf "$dst"
        cp -r "$module" "$dst"
        echo "  -> 模块 $module_name 已复制"
    fi
done

# ============================================================================
# Phase 4: 复制TVBoxOS app模块的libs/jniLibs/assets
# ============================================================================
echo "[Phase 4/9] 复制TVBoxOS app的libs/jniLibs/assets..."

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
# Phase 5: 核心 - 用TVBoxOS源码替换080java app中的反编译代码
# ============================================================================
echo "[Phase 5/9] 核心: 替换反编译的TVBox标准代码..."

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
# Phase 6: 清理反编译垃圾 + 处理ijkplayer
# ============================================================================
echo "[Phase 6/9] 清理反编译产物并处理ijkplayer..."

# 6.1 清理R.java
R_CLEANED=0
if [ -d "$OUTPUT_JAVA" ]; then
    while IFS= read -r rfile; do
        rm "$rfile"
        R_CLEANED=$((R_CLEANED + 1))
    done < <(find "$OUTPUT_JAVA" -name "R\$*.java" -o -name "R.java")
fi
echo "  -> 清理了 $R_CLEANED 个反编译R.java"

# 6.2 清理空的Java文件
EMPTY_CLEANED=0
if [ -d "$OUTPUT_JAVA" ]; then
    while IFS= read -r empty_file; do
        rm "$empty_file"
        EMPTY_CLEANED=$((EMPTY_CLEANED + 1))
    done < <(find "$OUTPUT_JAVA" -name "*.java" -size 0)
fi
echo "  -> 清理了 $EMPTY_CLEANED 个空文件"

# 6.3 处理ijkplayer
# 080java中可能有反编译的ijkplayer代码在 tv/danmaku/ijk/media/ 下
IJK_PATH="$OUTPUT_APP/src/main/java/tv/danmaku/ijk"
if [ -d "$IJK_PATH" ]; then
    echo "  -> 发现080java中的反编译ijkplayer代码，已删除（改用官方依赖）"
    rm -rf "$IJK_PATH"
fi

# 如果提供了官方ijkplayer源码，替换player模块中的ijkplayer
if [ -n "$IJKPLAYER_DIR" ] && [ -d "$OUTPUT_DIR/player" ]; then
    echo "  -> 用官方ijkplayer源码替换player模块中的ijkplayer..."

    # 找到player模块中ijkplayer相关的目录
    PLAYER_IJK="$OUTPUT_DIR/player/src/main/java/tv/danmaku/ijk"
    if [ -d "$PLAYER_IJK" ]; then
        rm -rf "$PLAYER_IJK"
        echo "  -> 已删除player模块中的旧ijkplayer代码"
    fi

    # 复制官方ijkplayer的Java代码
    IJK_JAVA="$IJKPLAYER_DIR/ijkplayer-java/src/main/java/tv/danmaku/ijk"
    if [ -d "$IJK_JAVA" ]; then
        mkdir -p "$PLAYER_IJK"
        cp -r "$IJK_JAVA/"* "$PLAYER_IJK/"
        echo "  -> 已复制官方ijkplayer Java代码"
    fi

    # 复制官方ijkplayer的so库（如果存在）
    IJK_JNILIBS="$IJKPLAYER_DIR/ijkplayer-java/src/main/jniLibs"
    if [ -d "$IJK_JNILIBS" ]; then
        mkdir -p "$OUTPUT_DIR/player/src/main/jniLibs"
        cp -r "$IJK_JNILIBS/"* "$OUTPUT_DIR/player/src/main/jniLibs/"
        echo "  -> 已复制官方ijkplayer jniLibs"
    fi

    echo "  -> ijkplayer已用官方源码替换"
else
    echo "  -> 使用TVBoxOS内置的ijkplayer（通过player模块依赖）"
fi

# ============================================================================
# Phase 7: 修复 app/build.gradle
# ============================================================================
echo "[Phase 7/9] 修复 app/build.gradle..."

KU9_BUILD="$KU9_APP/build.gradle"
TVBOX_BUILD="$TVBOX_APP/build.gradle"
OUTPUT_BUILD="$OUTPUT_APP/build.gradle"

if [ -f "$TVBOX_BUILD" ]; then
    # 备份080java的原始build.gradle
    cp "$OUTPUT_BUILD" "$OUTPUT_BUILD.ku9.bak"

    # 用TVBoxOS的build.gradle作为基础
    cp "$TVBOX_BUILD" "$OUTPUT_BUILD"

    # 提取酷9的关键配置并覆盖
    if [ -f "$KU9_BUILD" ]; then
        KU9_APPID=$(grep -oP "applicationId\s+'\K[^']+" "$KU9_BUILD" || echo "com.player.ku9py")
        KU9_VERSIONCODE=$(grep -oP "versionCode\s+\K[0-9]+" "$KU9_BUILD" || echo "1")
        KU9_VERSIONNAME=$(grep -oP "versionName\s+\"\K[^\"]+" "$KU9_BUILD" || echo "1.0.0")

        # 修改TVBoxOS build.gradle中的配置为酷9的
        sed -i "s/applicationId .*/applicationId '$KU9_APPID'/" "$OUTPUT_BUILD"
        sed -i "s/versionCode .*/versionCode $KU9_VERSIONCODE/" "$OUTPUT_BUILD"
        sed -i "s/versionName .*/versionName \"$KU9_VERSIONNAME\"/" "$OUTPUT_BUILD"

        echo "  -> build.gradle 已修复"
        echo "  -> 包名: $KU9_APPID | 版本: $KU9_VERSIONNAME ($KU9_VERSIONCODE)"
    fi
else
    echo "  [警告] 找不到TVBoxOS的app/build.gradle"
fi

# ============================================================================
# Phase 8: 保留酷9的res资源（UI布局、主题、图标）
# ============================================================================
echo "[Phase 8/9] 保留酷9UI资源..."

# TVBoxOS的Java代码已替换，但res资源保持080java的（酷9UI风格）
# 需要检查是否有TVBoxOS新增的layout资源需要补入

# 备份TVBoxOS的原始布局（供参考）
mkdir -p "$OUTPUT_DIR/tvbox_layout_backup"
if [ -d "$TVBOX_APP/src/main/res/layout" ]; then
    cp -r "$TVBOX_APP/src/main/res/layout" "$OUTPUT_DIR/tvbox_layout_backup/"
fi

# 检查TVBoxOS是否有080java缺少的layout文件
MISSING_LAYOUT=0
if [ -d "$TVBOX_APP/src/main/res/layout" ] && [ -d "$OUTPUT_APP/src/main/res/layout" ]; then
    while IFS= read -r layout_file; do
        layout_name=$(basename "$layout_file")
        if [ ! -f "$OUTPUT_APP/src/main/res/layout/$layout_name" ]; then
            cp "$layout_file" "$OUTPUT_APP/src/main/res/layout/$layout_name"
            MISSING_LAYOUT=$((MISSING_LAYOUT + 1))
            echo "  [补入] 缺少的layout: $layout_name"
        fi
    done < <(find "$TVBOX_APP/src/main/res/layout" -name "*.xml")
fi

if [ $MISSING_LAYOUT -gt 0 ]; then
    echo "  -> 补入了 $MISSING_LAYOUT 个TVBoxOS特有的layout"
else
    echo "  -> 酷9布局完整，无需补入"
fi

# ============================================================================
# Phase 9: 扫描并报告酷9特有文件
# ============================================================================
echo "[Phase 9/9] 扫描酷9特有文件..."

SPECIAL_FILE="$OUTPUT_DIR/KU9_SPECIAL_FILES.txt"
echo "# 酷9特有文件清单 (080java有但TVBoxOS没有)" > "$SPECIAL_FILE"
echo "# 这些文件包含酷9的特有功能，已完整保留" >> "$SPECIAL_FILE"
echo "" >> "$SPECIAL_FILE"

SPECIAL_COUNT=0
if [ -d "$KU9_JAVA" ] && [ -d "$TVBOX_JAVA" ]; then
    while IFS= read -r ku9_file; do
        rel_path="${ku9_file#$KU9_JAVA/}"
        # 跳过R.java
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
# 生成最终报告
# ============================================================================
echo ""
echo "生成合并报告..."

REPORT="$OUTPUT_DIR/MERGE_REPORT.md"

cat > "$REPORT" << EOF
# 酷9 + TVBoxOS + ijkplayer 合并报告

生成时间: $(date)

## 工程架构

```
ku9-final/
├── app/                    ← 酷9外壳 + TVBoxOS可编译源码
│   ├── src/main/java/      ← TVBoxOS源码替换反编译代码
│   ├── src/main/res/       ← 酷9UI资源（保留）
│   ├── libs/               ← 从TVBoxOS复制
│   └── build.gradle        ← TVBoxOS依赖 + 酷9版本信息
├── player/                 ← TVBoxOS播放器模块（含ijkplayer封装）
├── quickjs/                ← TVBoxOS QuickJS引擎模块
├── pyramid/                ← TVBoxOS Python支持模块
├── gradlew                 ← TVBoxOS构建脚本
├── settings.gradle         ← TVBoxOS模块配置
└── build.gradle            ← TVBoxOS根构建配置
```

## 合并统计

| 项目 | 数量 |
|------|------|
| 替换的反编译文件 | $REPLACED |
| 新增的TVBoxOS功能 | $ADDED |
| 清理的反编译R.java | $R_CLEANED |
| 清理的空文件 | $EMPTY_CLEANED |
| 补入的TVBoxOS layout | $MISSING_LAYOUT |
| 保留的酷9特有文件 | $SPECIAL_COUNT |

## 核心操作

### 1. 替换了什么？
用tytestelle/TVBoxOS的可编译源码，替换了080java中所有反编译的标准TVBox代码。

### 2. 保留了什么？
- 酷9的UI资源（layout, drawable, values, mipmap等）
- 酷9特有功能代码（LoginActivity, CrashActivity, Dialog, CustomView等）
- 酷9的版本信息（applicationId, versionCode, versionName）

### 3. ijkplayer处理
- 删除了080java中反编译的ijkplayer代码
- 使用TVBoxOS的player模块（含ijkplayer封装）
- 通过Gradle依赖引入官方ijkplayer库

## 编译命令

\`\`\`bash
cd $OUTPUT_DIR
chmod +x gradlew
./gradlew :app:assembleJavaDebug
\`\`\`

## 常见问题

**Q: 编译报错 "找不到符号 R.id.xxx"**
A: 酷9布局可能缺少TVBoxOS需要的View ID。查看错误中的ID名，
   从 \`tvbox_layout_backup/\` 中找到对应布局，把缺失的View复制到当前布局。

**Q: 编译报错 "找不到类 xxx"**
A: 可能是080java中某个酷9文件引用了被替换掉的类。检查报错位置，
   确认被引用的类是否在TVBoxOS源码中。如果不在，需要从080java补入。

**Q: 编译报错 "方法签名不匹配"**
A: 酷9代码调用了TVBoxOS中已更改的方法。需要修改调用处或恢复旧方法签名。

**Q: 直播界面是TVBoxOS风格**
A: 因为LivePlayActivity已替换为TVBoxOS版本（含EPG+台标+回放）。
   如需酷9风格，可从080java备份中提取UI代码移植。

## 文件速查

| 文件/目录 | 说明 |
|-----------|------|
| tvbox_layout_backup/ | TVBoxOS原始布局备份 |
| app/build.gradle.ku9.bak | 080java原始build.gradle备份 |
| KU9_SPECIAL_FILES.txt | 酷9特有文件清单 |

EOF

echo "  -> 报告已生成: $REPORT"

echo ""
echo "========================================"
echo "  合并完成！"
echo "========================================"
echo ""
echo "输出目录: $OUTPUT_DIR"
echo ""
echo "工程结构:"
ls -d "$OUTPUT_DIR"/*/
echo ""
echo "下一步:"
echo "  cd $OUTPUT_DIR"
echo "  chmod +x gradlew"
echo "  ./gradlew :app:assembleJavaDebug"
echo ""
echo "如有编译错误，把错误信息贴出来，我帮你逐个解决。"
echo ""
