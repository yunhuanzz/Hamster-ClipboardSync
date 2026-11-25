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
# 注意：原上游 imfuxiao/LibrimeKit 已不可用（404），改用自己的 fork（v0.2.0-octagram，含 octagram 语言模型组件）
LibrimeKitVersion="v0.2.0-octagram"
mkdir -p $OUTPUT
rm -rf $OUTPUT/*.xcframwork && (
  curl -OL https://github.com/yunhuanzz/LibrimeKit/releases/download/${LibrimeKitVersion}/Frameworks.tgz
  tar -zxf Frameworks.tgz -C ${OUTPUT}/..
  rm -rf Frameworks.tgz
)
