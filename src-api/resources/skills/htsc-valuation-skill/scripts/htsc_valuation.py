#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""华泰研究所估值模型接口客户端"""

import argparse
import json
import os
import sys

import requests

BASE_GATEWAY_URL = "https://inst.htsc.com/institution/skill/tool/apiGateway"
BASE_DOWNLOAD_URL = (
    "https://inst.htsc.com/institution/inst_plat_app/file/storage/standardToolDownload"
)

RISK_WARNING = (
    "以上内容由 AI 基于华泰证券研究报告及其附属成果总结生成，可能省略完整报告中的重要信息、"
    "市场风险、业绩不及预期等风险，请务必阅读完整原始报告。有关数据、观点、评级等具有时效性，"
    "请自行核实最新信息。以上内容仅供研究学习使用，不构成任何投资建议。请勿二次传播并自行承担投资风险。"
)


def get_app_key():
    app_key = os.environ.get("HTSC_APP_KEY")
    if not app_key:
        print("错误：环境变量 HTSC_APP_KEY 未设置。", file=sys.stderr)
        print("请先设置环境变量，例如：", file=sys.stderr)
        print('  export HTSC_APP_KEY="your_app_key_here"', file=sys.stderr)
        sys.exit(1)
    return app_key


def make_headers():
    return {
        "Authorization": get_app_key(),
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json; charset=utf-8",
    }


def query_valuation_file(secu_abbr):
    payload = {
        "channel": "ris",
        "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
        "method": "SkillCommonApi",
        "skillName": "htsc-valuation-skill",
        "params": {
            "resource": "queryValuationFile",
            "secuAbbr": secu_abbr,
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


def query_valuation_data(secu_abbr, index_abbr):
    payload = {
        "channel": "ris",
        "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
        "method": "SkillCommonApi",
        "skillName": "htsc-valuation-skill",
        "params": {
            "resource": "queryValuationData",
            "secuAbbr": secu_abbr,
            "indexAbbr": index_abbr,
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


def download_file(file_id, save_path):
    payload = {"fileId": file_id}
    headers = {
        "Authorization": get_app_key(),
        "Content-Type": "application/json; charset=utf-8",
    }
    resp = requests.post(
        BASE_DOWNLOAD_URL,
        headers=headers,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        timeout=120,
        stream=True,
    )
    resp.raise_for_status()
    with open(save_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            if chunk:
                f.write(chunk)
    return save_path


def print_data_result(data):
    """格式化打印查询数据结果，标注数据来源和研报信息。"""
    result_data = data.get("resultData") or {}
    title = result_data.get("title", "")
    pub_date = result_data.get("pubDate", "")
    print("数据来源：华泰证券研究所")
    print()
    if title:
        print(f"模型关联研报标题：{title}")
    if pub_date:
        print(f"研报外发时间：{pub_date}")
    if title or pub_date:
        print()

    data_list = result_data.get("dataList", [])
    if not data_list:
        print("未查询到数据。")
    else:
        for item in data_list:
            unit = item.get("unit", "")
            index_name = item.get("indexName", "")
            currency = item.get("currency", "")
            year_data = item.get("dataList", [])

            print(f"指标：{index_name}")
            if unit:
                print(f"单位：{unit}")
            if currency:
                print(f"币种：{currency}")
            print()

            if year_data:
                print(f"{'年份':<6} {'数值类型':<8} {'数值':<15}")
                print("-" * 30)
                for yd in year_data:
                    year = yd.get("year", "")
                    value_type = yd.get("valueType", "")
                    value = yd.get("value", "")
                    type_str = "实际值" if value_type == 1 else ("预测值" if value_type == 2 else str(value_type))
                    value_str = "" if value is None else str(value)
                    print(f"{year:<6} {type_str:<8} {value_str:<15}")
            print()

    print(f"风险揭示：{RISK_WARNING}")


def print_file_info(data):
    """格式化打印文件信息，标注数据来源和研报信息。"""
    result_data = data.get("resultData") or {}
    title = result_data.get("title", "")
    pub_date = result_data.get("pubDate", "")
    gateway_file_id = result_data.get("gatewayFileId", "")
    annex_name = result_data.get("annexName", "")
    annex_format = result_data.get("annexFormat", "")
    print("数据来源：华泰证券研究所")
    print()
    if title:
        print(f"模型关联研报标题：{title}")
    if pub_date:
        print(f"研报外发时间：{pub_date}")
    if title or pub_date:
        print()

    print(f"文件名称：{annex_name}")
    print(f"文件格式：{annex_format}")
    print(f"网关文件ID：{gateway_file_id}")
    print()
    print(f"风险揭示：{RISK_WARNING}")


def main():
    parser = argparse.ArgumentParser(description="华泰研究所估值模型接口客户端")
    subparsers = parser.add_subparsers(dest="command", required=True)

    file_parser = subparsers.add_parser("file", help="查询估值模型文件信息")
    file_parser.add_argument("secu_abbr", help="公司简称")

    data_parser = subparsers.add_parser("data", help="查询估值数据")
    data_parser.add_argument("secu_abbr", help="公司简称")
    data_parser.add_argument("index_abbr", help="表名或指标名（如：利润表、营业收入）")

    download_parser = subparsers.add_parser("download", help="下载估值模型文件")
    download_parser.add_argument("file_id", help="网关文件ID")
    download_parser.add_argument("save_path", help="保存路径")

    args = parser.parse_args()

    if args.command == "file":
        result = query_valuation_file(args.secu_abbr)
        if result.get("code") == "0":
            print_file_info(result)
        else:
            print(f"查询失败：{result.get('msg', '未知错误')}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "data":
        result = query_valuation_data(args.secu_abbr, args.index_abbr)
        if result.get("code") == "0":
            print_data_result(result)
        else:
            print(f"查询失败：{result.get('msg', '未知错误')}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "download":
        download_file(args.file_id, args.save_path)
        print(f"文件已下载至：{args.save_path}")


if __name__ == "__main__":
    main()
