#!/usr/bin/env bash
# encoding: utf-8
set -e

# 输入方案临时目录
if [[ -z "${CI_PRIMARY_REPOSITORY_PATH}" ]]; then
  CI_PRIMARY_REPOSITORY_PATH="$PWD"
  WORK=`pwd`
else
  CI_PRIMARY_REPOSITORY_PATH="${CI_PRIMARY_REPOSITORY_PATH}"
  WORK="${CI_PRIMARY_REPOSITORY_PATH}"
fi

# 如果方案存在就不再执行
# if [[  -f Resources/SharedSupport/SharedSupport.zip ]]
# then
#   exit 0
# fi

# 下载已编译过的rimelib
rime_version=1.8.5
rime_git_hash=08dd95f
if [[ ! -d .deps ]] 
then
  rime_archive="rime-${rime_git_hash}-macOS.tar.bz2"
  rime_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_archive}"

  rime_deps_archive="rime-deps-${rime_git_hash}-macOS.tar.bz2"
  rime_deps_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_deps_archive}"

  rm -rf .deps && mkdir -p .deps && (
      cd .deps
      [ -z "${no_download}" ] && curl -LO "${rime_download_url}"
      tar --bzip2 -xf "${rime_archive}"
      [ -z "${no_download}" ] && curl -LO "${rime_deps_download_url}"
      tar --bzip2 -xf "${rime_deps_archive}"
  )
fi



OUTPUT="$CI_PRIMARY_REPOSITORY_PATH/.tmp"
DST_PATH="$OUTPUT/SharedSupport"
rm -rf .plum $OUTPUT
mkdir -p $DST_PATH/opencc
cp -r .deps/share/opencc $DST_PATH

git clone --depth 1 https://github.com/rime/plum.git $OUTPUT/.plum

for package in prelude rime-essay; do
  bash $OUTPUT/.plum/scripts/install-packages.sh "${package}" $DST_PATH
done

# 绘文字
# 方案来源: https://github.com/rime/rime-emoji
rime_emoji_version="15.0"
rime_emoji_archive="rime-emoji-${rime_emoji_version}.zip"
rime_emoji_download_url="https://github.com/rime/rime-emoji/archive/refs/tags/${rime_emoji_version}.zip"
rm -rf $OUTPUT/.emoji && mkdir -p $OUTPUT/.emoji && (
    cd $OUTPUT/.emoji
    [ -z "${no_download}" ] && curl -Lo "${rime_emoji_archive}" "${rime_emoji_download_url}"
    unzip "${rime_emoji_archive}" -d .
    rm -rf ${rime_emoji_archive}
    cd rime-emoji-${rime_emoji_version}
    for target in category word; do
      ${WORK}/.deps/bin/opencc -c ${WORK}/.deps/share/opencc/t2s.json -i opencc/emoji_${target}.txt > ${target}.txt
      # workaround for rime/rime-emoji#48
      # macOS sed 和 GNU sed 不同，见 https://stackoverflow.com/a/4247319/6676742
      sed -i'.original' -e 's/鼔/鼓/g' ${target}.txt
      cat ${target}.txt opencc/emoji_${target}.txt | awk '!seen[$1]++' > ../emoji_${target}.txt
    done
  ) && \
cp ${OUTPUT}/.emoji/emoji_*.txt ${DST_PATH}/opencc/ && \
cp ${OUTPUT}/.emoji/rime-emoji-${rime_emoji_version}/opencc/emoji.json ${DST_PATH}/opencc/

# 整理 DST_PATH 输入方案文件, 生成最终版版本default.yaml
pushd "${DST_PATH}" > /dev/null

# 通过 schema_list.yaml 内容 改写 default.yaml 中 scheme_list 中内容
echo '' > schema_list.yaml
sed '{
  s/^config_version: \(["]*\)\([0-9.]*\)\(["]*\)$/config_version: \1\2.minimal\3/
  /- schema:/d
  /^schema_list:$/r schema_list.yaml
}' default.yaml > default.yaml.min
rm schema_list.yaml
mv default.yaml.min default.yaml

popd > /dev/null

# SharedSupport
mkdir -p $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport
(
  cp $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/hamster.yaml $DST_PATH
  cd $DST_PATH/
  zip -r SharedSupport.zip *
) && cp $DST_PATH/SharedSupport.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/

# 内置方案雾凇
input_scheme_name=rime-ice

rm -rf $OUTPUT/.$input_scheme_name && \
  git clone --depth 1 https://github.com/iDvel/$input_scheme_name $OUTPUT/.$input_scheme_name && (
    cd $OUTPUT/.$input_scheme_name
    # 提前编译
    # export DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH:$WORK/.deps/dist/lib
    # $WORK/.deps/dist/bin/rime_deployer --build .
    zip -r $input_scheme_name.zip ./*
  ) && \
  cp -R $OUTPUT/.$input_scheme_name/*.zip $CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/


# 本地语言模型 (变体 B, 蒸馏版): mizorewww/rime-qwen-freq v0.4.0 的
# qwen14b-zh-hans.gram (Qwen3-14B 离线蒸馏, 实测 11,935,788 字节约 11.4MB)。
# Release 只提供 .gz, 先下载校验再解压 (见下); IPA 约 69MB -> 约 41MB。
# 文件不进 git (见 .gitignore), 以散文件放进 Resources/SharedSupport/ (不在
# SharedSupport.zip 里, 原因同上: zip 只在首次运行/重置时才解压)。
# 运行时 deployment()/syncRime() 会把它拷进沙盒 SharedSupport, 再同步到 App Group。
gram_file="qwen14b-zh-hans.gram"
gram_sha256="b655cc8d4bf0097cc06c46c37238f3880db6e19b7cd996637ed1cb253336e8ce"
gram_gz_url="https://github.com/mizorewww/rime-qwen-freq/releases/download/v0.4.0/qwen14b-zh-hans.gram.gz"
gram_gz_sha256="e1be79d20ea469efef8336d4952d27e7b9a0c676df973fea3f8f65428fdf5b75"
gram_dst="$CI_PRIMARY_REPOSITORY_PATH/Resources/SharedSupport/${gram_file}"
gram_actual_sha256=""
if [[ -f "$gram_dst" ]]; then
  gram_actual_sha256="$(shasum -a 256 "$gram_dst" | awk '{print $1}')"
fi
if [[ "$gram_actual_sha256" != "$gram_sha256" ]]; then
  gram_gz_dst="${gram_dst}.gz"
  [ -z "${no_download}" ] && curl -L -o "$gram_gz_dst" "$gram_gz_url"
  gram_gz_actual_sha256="$(shasum -a 256 "$gram_gz_dst" 2>/dev/null | awk '{print $1}')" || gram_gz_actual_sha256=""
  if [[ "$gram_gz_actual_sha256" != "$gram_gz_sha256" ]]; then
    echo "ERROR: ${gram_file}.gz SHA256 mismatch (got $gram_gz_actual_sha256, want $gram_gz_sha256)" >&2
    exit 1
  fi
  gunzip -c "$gram_gz_dst" > "$gram_dst"
  rm -f "$gram_gz_dst"
  gram_actual_sha256="$(shasum -a 256 "$gram_dst" 2>/dev/null | awk '{print $1}')" || gram_actual_sha256=""
fi
if [[ "$gram_actual_sha256" != "$gram_sha256" ]]; then
  echo "ERROR: $gram_file SHA256 mismatch (got $gram_actual_sha256, want $gram_sha256)" >&2
  exit 1
fi

