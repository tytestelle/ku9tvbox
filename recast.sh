name: 重铸酷9 (基于TVBoxOS骨架)

on:
  workflow_dispatch:
    inputs:
      ku9_repo:
        description: '酷9仓库'
        default: '9602894/080java'
      ku9_branch:
        default: 'main'
      tvbox_repo:
        description: 'TVBoxOS仓库'
        default: 'tytestelle/TVBoxOS'
      tvbox_branch:
        default: 'main'

jobs:
  recast:
    runs-on: ubuntu-latest
    steps:
      - name: 检出工作流
        uses: actions/checkout@v4
        with:
          path: workflow

      - name: 检出酷9
        uses: actions/checkout@v4
        with:
          repository: ${{ github.event.inputs.ku9_repo }}
          ref: ${{ github.event.inputs.ku9_branch }}
          path: ku9

      - name: 检出TVBoxOS
        uses: actions/checkout@v4
        with:
          repository: ${{ github.event.inputs.tvbox_repo }}
          ref: ${{ github.event.inputs.tvbox_branch }}
          path: tvbox

      - name: 执行重铸脚本
        run: |
          chmod +x workflow/recast.sh
          workflow/recast.sh ./ku9 ./tvbox ./output 2>&1 | tee recast.log

      - name: 设置JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: 设置Android SDK
        uses: android-actions/setup-android@v3

      - name: 创建local.properties
        run: |
          echo "sdk.dir=$ANDROID_SDK_ROOT" > ./output/local.properties

      - name: 编译
        id: compile
        run: |
          cd output
          chmod +x gradlew
          ./gradlew :app:assembleJavaDebug --stacktrace 2>&1 | tee compile.log || true
          if [ -f "app/build/outputs/apk/java/debug/TVBox_debug-java.apk" ]; then
            echo "SUCCESS=true" >> $GITHUB_ENV
          else
            echo "SUCCESS=false" >> $GITHUB_ENV
            grep -E "error:|Error:|FAILED" compile.log | head -200 > errors.txt
          fi
        continue-on-error: true

      - name: 上传产物
        uses: actions/upload-artifact@v4
        with:
          name: recast-project
          path: output/
          retention-days: 7
