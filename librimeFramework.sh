#!/usr/bin/env bash
# encoding: utf-8
set -e

OUTPUT="${PWD}/Frameworks"

# 如果存在就不再执行
# if [[ -d ${OUTPUT} ]]
# then
#   exit 0
# fi

# 下载依赖的 librime framework
# 注意：原上游 imfuxiao/LibrimeKit 已不可用（404），改用自己的 fork（v0.3.0-octagram，含 octagram 语言模型组件）
# 引擎版本：v0.3.0-octagram 标签当前指向 LibrimeKit b016145（Round 18c：新增 RimeReplaceInput 一次性替换 API，9 键点选卡顿根治；含 d1）
LibrimeKitVersion="v0.3.0-octagram"
mkdir -p $OUTPUT
rm -rf $OUTPUT/*.xcframwork && (
  curl -OL https://github.com/yunhuanzz/LibrimeKit/releases/download/${LibrimeKitVersion}/Frameworks.tgz
  tar -zxf Frameworks.tgz -C ${OUTPUT}/..
  rm -rf Frameworks.tgz
)
