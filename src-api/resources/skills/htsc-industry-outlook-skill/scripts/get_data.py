#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
华泰研究所行业周度观点数据获取模块
从 API 接口获取数据，支持动态 Authorization
"""

import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

import requests

# 配置项
API_BASE_URL = "https://inst.htsc.com"
API_PATH = "/institution/skill/tool/apiGateway"
TIMEOUT_SECONDS = 60

os.environ['no_proxy'] = '*'


def extract_date_from_query(query: str) -> Optional[str]:
    """
    从用户查询中提取日期。

    支持的日期格式：
    - YYYY-MM-DD (如 2026-05-12)
    - YYYY/MM/DD (如 2026/05/12)
    - YYYY年MM月DD日 (如 2026年05月12日)
    - YYYYMMDD (如 20260512)

    Args:
        query: 用户输入的查询字符串

    Returns:
        str: 标准化后的日期字符串 YYYY-MM-DD，如果没有找到日期则返回 None
    """
    if not query:
        return None

    # 匹配 YYYY-MM-DD
    match = re.search(r'(\d{4})-(\d{1,2})-(\d{1,2})', query)
    if match:
        year, month, day = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"

    # 匹配 YYYY/MM/DD
    match = re.search(r'(\d{4})/(\d{1,2})/(\d{1,2})', query)
    if match:
        year, month, day = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"

    # 匹配 YYYY年MM月DD日
    match = re.search(r'(\d{4})年(\d{1,2})月(\d{1,2})日', query)
    if match:
        year, month, day = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"

    # 匹配 YYYYMMDD（8位数字，且为合理日期）
    match = re.search(r'(\d{4})(\d{2})(\d{2})', query)
    if match:
        year, month, day = match.groups()
        try:
            dt = datetime(int(year), int(month), int(day))
            # 确保是合理的日期
            if 2020 <= dt.year <= 2030:
                return f"{year}-{month}-{day}"
        except ValueError:
            pass

    return None


def build_request_body(date: Optional[str] = None) -> Dict[str, Any]:
    """
    构建请求 body

    Args:
        date: 日期字符串 YYYY-MM-DD，如果没有则不传 date 字段

    Returns:
        dict: 请求 body
    """
    params = {"resource": "queryWeeklyIndustryOutlook"}
    if date:
        params["date"] = date

    return {
        "channel": "ris",
        "skillName": "htsc-industry-outlook-skill",
        "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
        "method": "SkillCommonApi",
        "params": params,
    }


def fetch_data_from_api(
    query: str = "",
    api_key: Optional[str] = None,
    date: Optional[str] = None,
) -> Dict[str, Any]:
    """
    从 API 获取华泰研究所行业周度观点数据

    Args:
        query: 用户查询字符串（用于提取日期）
        api_key: API 密钥，用于 Authorization 头
        date: 直接指定的日期，优先级高于从 query 提取

    Returns:
        dict: API 返回的数据

    Raises:
        ValueError: 当 api_key 为空时
        RuntimeError: 当 API 请求失败时
    """
    # 获取 api_key
    if not api_key:
        api_key = os.getenv("HTSC_APP_KEY")

    if not api_key:
        raise ValueError(
            "未识别到您的API KEY，请前往行知 App 或行知网页版，进入“华泰智研 Skill 及 MCP 专区”，点击“API KEY”查看并复制您的专属认证码。"
        )

    # 确定日期
    target_date = date or extract_date_from_query(query)

    # 构建请求
    url = f"{API_BASE_URL}{API_PATH}"
    body = build_request_body(target_date)
    headers = {
        "Content-Type": "application/json",
        "Authorization": api_key,
    }

    try:
        response = requests.post(
            url,
            headers=headers,
            json=body,
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()

    except requests.exceptions.Timeout:
        raise RuntimeError(f"请求超时（{TIMEOUT_SECONDS}秒）")
    except requests.exceptions.ConnectionError as e:
        raise RuntimeError(f"连接失败: {str(e)}")
    except requests.exceptions.HTTPError as e:
        raise RuntimeError(f"HTTP 错误: {e.response.status_code} - {e.response.text}")
    except requests.exceptions.RequestException as e:
        raise RuntimeError(f"请求异常: {str(e)}")
    except json.JSONDecodeError:
        raise RuntimeError("响应不是合法的 JSON 格式")


# 英文字段名 -> 中文字段名 映射
FIELD_NAME_MAP = {
    "fundamentals": "基本面",
    "marginalChange": "本周边际变化",
    "leaderStockAnalysis": "龙头个股分析（一支）",
    "configSuggestion": "参考思路（一级行业）",
    "annualGoodNewsRate": "年报预喜率",
    "calendarEffect": "月历效应",
    "inducode": "行业代码",
    "induname": "一级行业",
    "sectorOption": "赛道意见",
    "valuation": "估值",
    "sortTimeDeal": "短期交易",
    "risk": "潜在风险",
    "sector": "赛道",
    "valuationDesc": "综述",
    "valuationPe": "PE",
    "valuationPeQuantitle": "PE分位数（%）",
    "valuationPb": "PB",
    "valuationPbQuantitle": "PB分位数（%）",
}


def _translate_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """将单个行业记录的英文字段名翻译为中文"""
    if not isinstance(item, dict):
        return item
    result = {}
    for key, value in item.items():
        cn_key = FIELD_NAME_MAP.get(key, key)
        result[cn_key] = value
    return result


def _translate_sectors(sectors: Dict[str, Any]) -> Dict[str, Any]:
    """翻译所有 sector 下的行业记录字段名"""
    if not isinstance(sectors, dict):
        return sectors
    result = {}
    for sector_name, items in sectors.items():
        if isinstance(items, list):
            result[sector_name] = [_translate_item(item) for item in items]
        else:
            result[sector_name] = items
    return result


def parse_api_response(response_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    解析 API 响应，提取行业周度观点数据

    Args:
        response_data: API 原始响应

    Returns:
        dict: 解析后的数据，格式与原有 JSON 文件一致（字段名为中文）

    Raises:
        RuntimeError: 当响应格式异常或业务错误时
    """
    if not isinstance(response_data, dict):
        raise RuntimeError(f"响应格式异常: 期望 dict，实际为 {type(response_data)}")

    code = response_data.get("code")
    if code is not None and str(code) != "0" and str(code) != "200":
        msg = response_data.get("msg", response_data.get("message", "未知错误"))
        raise RuntimeError(f"接口返回错误: [{code}] {msg}")

    data = response_data.get("resultData")
    if data is None:
        raise RuntimeError("响应中未找到 resultData 字段")

    if not isinstance(data, dict):
        raise RuntimeError(f"resultData 格式异常: 期望 dict，实际为 {type(data)}")

    return {
        "date": data.get("date", ""),
        "sectors": _translate_sectors(data.get("sectors", {})),
    }


def get_industry_outlook_data(
    query: str = "",
    api_key: Optional[str] = None,
    date: Optional[str] = None,
) -> Dict[str, Any]:
    """
    获取华泰研究所行业周度观点数据（完整流程）

    Args:
        query: 用户查询字符串
        api_key: API 密钥
        date: 直接指定的日期

    Returns:
        dict: 解析后的行业观点数据
    """
    response_data = fetch_data_from_api(query=query, api_key=api_key, date=date)
    return parse_api_response(response_data)
