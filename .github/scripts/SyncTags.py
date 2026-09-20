#!/usr/bin/env python3
"""同步 ImmortalWrt 版本标签到 AutoBuild.yml 的下拉选项。

由 .github/workflows/SyncVersions.yml 调用。

背景：GitHub Actions 的 workflow_dispatch 下拉选项（type: choice）必须静态写在
工作流文件中，官方不支持运行时动态生成。因此用定时工作流改写 options 列表。

用法：
    python3 .github/scripts/SyncTags.py <AutoBuild.yml 路径> <标签文件路径> [保留数量]

标签文件每行一个标签，按版本从新到旧排列。
"""

import re
import sys

import yaml

# AutoBuild.yml 中的固定缩进（6/8/10 空格）
BLOCK_HEAD = '      tag:\n'
OPTIONS_KEY = '        options:\n'
ITEM_INDENT = '          '

# 所有输入项名称，用于校验更新后没有丢项
EXPECTED_INPUTS = ('device', 'tag', 'cache_enabled', 'disk_cleanup', 'skip_compile')


def build_pattern():
    """匹配 tag 输入块的 options 区间。"""
    return re.compile(
        r'(?m)^(      tag:\n(?:        .*\n)*?        options:\n)((?:          - .*\n)+)'
    )


def parse_options(block: str) -> list[str]:
    """从 options 块解析出当前的值列表。"""
    values = []
    for line in block.splitlines():
        line = line.strip()
        if not line:
            continue
        values.append(re.sub(r'^- "?|"?$', '', line))
    return values


def main() -> int:
    if len(sys.argv) < 3:
        print('用法: SyncTags.py <AutoBuild.yml> <标签文件> [保留数量]')
        return 2

    build_path, tags_path = sys.argv[1], sys.argv[2]
    keep = int(sys.argv[3]) if len(sys.argv) > 3 else 8

    with open(build_path, encoding='utf-8') as f:
        text = f.read()

    with open(tags_path, encoding='utf-8') as f:
        tags = [line.strip() for line in f if line.strip()]

    if not tags:
        print('[ERROR] 标签文件为空')
        return 1

    selected = tags[:keep]

    match = build_pattern().search(text)
    if not match:
        print('[ERROR] 未在 %s 中找到 tag.options 结构，请检查缩进是否被改动' % build_path)
        return 1

    old_values = parse_options(match.group(2))
    desired = ['latest'] + selected

    if old_values == desired:
        print('[OK] 选项已是最新，无需修改')
        print('当前选项: %s' % ', '.join(old_values))
        return 0

    print('旧选项: %s' % ', '.join(old_values))
    print('新选项: %s' % ', '.join(desired))

    new_block = ITEM_INDENT + '- latest\n' + ''.join(
        '%s- "%s"\n' % (ITEM_INDENT, tag) for tag in selected
    )
    updated = text[:match.start(2)] + new_block + text[match.end(2):]

    # 写回前做结构化校验，避免写坏工作流
    try:
        doc = yaml.safe_load(updated)
    except Exception as exc:
        print('[ERROR] 更新后 YAML 解析失败，放弃写入: %s' % exc)
        return 1

    inputs = doc[True]['workflow_dispatch']['inputs']

    if inputs['tag']['options'] != desired:
        print('[ERROR] 更新后 tag.options 与预期不一致: %s' % inputs['tag']['options'])
        return 1

    if inputs['tag'].get('default') != 'latest':
        print('[ERROR] tag.default 被意外改动')
        return 1

    for name in EXPECTED_INPUTS:
        if name not in inputs:
            print('[ERROR] 输入项 %s 丢失' % name)
            return 1

    with open(build_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(updated)

    print('[OK] 已更新 %s: latest + %d 个历史版本' % (build_path, len(selected)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
