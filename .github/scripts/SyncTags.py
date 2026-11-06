#!/usr/bin/env python3
"""把 ImmortalWrt 版本标签同步到编译工作流的 tag 下拉选项。

workflow_dispatch 的 choice 选项不能运行时生成，只能由定时工作流改写文件
（调用方：.github/workflows/SyncVersions.yml）。

用法：python3 .github/scripts/SyncTags.py <工作流 yml> <标签文件> [保留数量]
标签文件每行一个标签，从新到旧；支持的工作流见 EXPECTED_INPUTS_BY_FILE
（当前仅 FullBuild.yml）。
"""

import os
import re
import sys

import yaml

# 各工作流中的固定缩进（6/8/10 空格）
BLOCK_HEAD = '      tag:\n'
OPTIONS_KEY = '        options:\n'
ITEM_INDENT = '          '

# 各工作流应有的 workflow_dispatch 输入项，增删输入项时必须同步本表。
# 键为工作流文件名，值为该文件应有的全部输入项。
EXPECTED_INPUTS_BY_FILE = {
    'FullBuild.yml': (
        'device',
        'tag',
        'cache_enabled',
        'skip_compile',
        'ruby_yjit',
    ),
}


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
        print('用法: SyncTags.py <工作流 yml> <标签文件> [保留数量]')
        return 2

    build_path, tags_path = sys.argv[1], sys.argv[2]
    keep = int(sys.argv[3]) if len(sys.argv) > 3 else 8

    # 未登记的工作流直接拒绝，避免写坏不认识的文件
    wf_name = os.path.basename(build_path)
    expected_inputs = EXPECTED_INPUTS_BY_FILE.get(wf_name)
    if expected_inputs is None:
        print('[ERROR] 未登记的工作流文件: %s' % wf_name)
        print('        请在 SyncTags.py 的 EXPECTED_INPUTS_BY_FILE 中登记其输入项')
        return 1

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

    # 双向校验：既查丢失，也查新增/改名（只查丢失会漏掉后两种情况）
    actual = set(inputs)
    expected = set(expected_inputs)

    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)

    if missing:
        print('[ERROR] 输入项丢失: %s' % ', '.join(missing))
        return 1

    if unexpected:
        print('[ERROR] 出现未登记的输入项: %s' % ', '.join(unexpected))
        print('        请同步更新 SyncTags.py 的 EXPECTED_INPUTS_BY_FILE')
        return 1

    with open(build_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(updated)

    print('[OK] 已更新 %s: latest + %d 个历史版本' % (build_path, len(selected)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
