#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""华泰研究所每日复盘接口客户端"""

import argparse
import json
import os
import sys

import requests

BASE_GATEWAY_URL = "https://inst.htsc.com/institution/skill/tool/apiGateway"


def _setup_stdout_encoding():
    """确保 stdout 使用 utf-8 编码，避免 Windows 下 gbk 编码错误。"""
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        # Python < 3.7 兼容
        pass


def _safe_print(text):
    """安全输出，遇到编码错误时自动降级处理。"""
    try:
        print(text)
    except UnicodeEncodeError:
        try:
            print(text.encode("utf-8", errors="replace").decode("utf-8", errors="replace"))
        except UnicodeEncodeError:
            print(text.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(sys.stdout.encoding or "utf-8", errors="replace"))


def get_app_key():
    app_key = os.environ.get("HTSC_APP_KEY")
    if not app_key:
        _safe_print("错误：环境变量 HTSC_APP_KEY 未设置。")
        _safe_print("请先设置环境变量，例如：")
        if sys.platform == "win32":
            _safe_print('  set HTSC_APP_KEY=your_app_key_here')
        else:
            _safe_print('  export HTSC_APP_KEY="your_app_key_here"')
        sys.exit(1)
    return app_key


def make_headers():
    return {
        "Authorization": get_app_key(),
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json; charset=utf-8",
    }


def query_daily_review(query_type):
    payload = {
        "channel": "ris",
        "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
        "method": "SkillCommonApi",
        "skillName": "htsc-daily-review-skill",
        "params": {
            "resource": "queryDailyReview",
            "queryType": str(query_type),
        },
    }
    resp = requests.post(
        BASE_GATEWAY_URL,
        headers=make_headers(),
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def print_review_result(data):
    """格式化打印复盘结果，标注数据来源和分析师信息。"""
    result_data = data.get("resultData", [])

    _safe_print("数据来源：华泰证券研究所")
    _safe_print("")

    if not result_data:
        _safe_print("未查询到复盘数据。")
        return

    for idx, item in enumerate(result_data, start=1):
        title = item.get("title", "")
        review = item.get("review", "")
        pub_date = item.get("pubDate", "")

        if len(result_data) > 1:
            _safe_print(f"=== 第 {idx} 条 ===")

        if pub_date:
            _safe_print(f"复盘日期：{pub_date}")
        if title:
            _safe_print(f"标题：{title}")

        _safe_print("")

        if review:
            _safe_print("【市场复盘】")
            _safe_print(review)

        if idx < len(result_data):
            _safe_print("")
            _safe_print("-" * 40)
            _safe_print("")

    _safe_print("")
    _safe_print("=" * 40)
    _safe_print("风险揭示：以上内容由 AI 基于华泰证券研究报告及其附属成果总结生成，可能省略完整报告中的重要信息、市场风险、业绩不及预期等风险，请务必阅读完整原始报告。有关数据、观点、评级等具有时效性，请自行核实最新信息。以上内容仅供研究学习使用，不构成任何投资建议。请勿二次传播并自行承担投资风险。")
    _safe_print("=" * 40)


def main():
    _setup_stdout_encoding()

    parser = argparse.ArgumentParser(description="华泰研究所每日复盘接口客户端")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("recent", help="查询最近一个交易日的复盘数据")
    subparsers.add_parser("week", help="查询最近5个交易日的复盘数据")

    args = parser.parse_args()

    if args.command == "recent":
        query_type = 1
    elif args.command == "week":
        query_type = 2
    else:
        parser.print_help()
        sys.exit(1)

    result = query_daily_review(query_type)
    if result.get("code") == "0":
        print_review_result(result)
    else:
        _safe_print(f"查询失败：{result.get('msg', '未知错误')}")
        sys.exit(1)


if __name__ == "__main__":
    main()
