#!/usr/bin/env python3
"""
华泰证券研报查询脚本
调用 RIS 接口获取最新的5篇研报
"""

import os
import sys
import json
import argparse
from typing import Optional, List

# 优先使用 urllib（标准库），避免外部依赖
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError


API_URL = "https://inst.htsc.com/institution/skill/tool/apiGateway"
ENV_KEY_NAME = "HTSC_APP_KEY"

# 华泰行业体系有效行业名称白名单（来源：RIS_INDUSTRY_DICT_NEW.csv）
# rankChanges 有效取值
VALID_RANK_CHANGES = frozenset(["首评", "上调", "下调", "维持"])

# macroResearch 有效取值（总量研究方向）
VALID_MACRO_RESEARCH = frozenset(["宏观", "固定收益", "策略", "金工"])

# strategicResearch 有效取值（战略研究细分类型）
VALID_STRATEGIC_RESEARCH = frozenset(["经济政策与国际关系", "能源转型", "先进制造战略"])

VALID_INDUSTRIES = frozenset(
    [
        "K12教育",
        "专用材料",
        "专用设备",
        "中药",
        "乘用车",
        "互联网",
        "互联网媒体",
        "交通运输",
        "仓储物流",
        "传媒",
        "供热及其他",
        "保险",
        "信托",
        "光学光电子",
        "全国性股份制银行",
        "公用事业",
        "公用环保",
        "公路运输",
        "兵器兵装",
        "其他交运设备",
        "其他军工",
        "其他多元金融",
        "其他建材",
        "其他服务",
        "其他电子",
        "其他金属非金属新材料及加工",
        "农业综合",
        "农产品加工",
        "农林牧渔",
        "农用化工",
        "出版与广播",
        "包装印刷",
        "化妆品",
        "化学制品",
        "化学制药",
        "化学原料",
        "化学纤维",
        "区域性银行",
        "医疗器械",
        "医疗服务",
        "医药健康",
        "医药商业",
        "半导体",
        "博彩",
        "厨房电器",
        "发电",
        "可选消费",
        "商业贸易",
        "商用车",
        "园区开发",
        "国有大型银行",
        "基本金属及加工",
        "基础化工",
        "基础材料",
        "多元金融",
        "家居用品",
        "家用电器",
        "小家电",
        "工业",
        "工程机械",
        "废物管理",
        "建材",
        "建筑与工程",
        "建筑施工",
        "建筑装修",
        "建筑设计及服务",
        "必选消费",
        "房地产",
        "房地产中介业务",
        "房地产开发",
        "房地产服务",
        "教育信息化",
        "教育和人力资源",
        "文化娱乐",
        "新能源及动力系统",
        "旅游综合",
        "早幼教",
        "普钢",
        "景点",
        "有色金属",
        "服装",
        "机场",
        "机械设备",
        "材料和零部件",
        "林业",
        "检测及服务",
        "橡塑制品",
        "水泥",
        "水路运输",
        "汽车",
        "汽车销售及服务",
        "汽车零部件",
        "消费电子",
        "消费轻工",
        "渔业",
        "港口",
        "煤炭",
        "燃气及分销",
        "物业管理",
        "特钢",
        "环保",
        "环保及水务",
        "环保工程及服务",
        "玻璃",
        "生物医药",
        "电力设备与新能源",
        "电子",
        "电子元件",
        "电子商务",
        "电气设备",
        "电源设备",
        "电网",
        "白色家电",
        "石油化工",
        "石油天然气",
        "石油（天然气）开采",
        "社会服务",
        "种植业",
        "科技",
        "租赁",
        "稀有金属",
        "纺织",
        "纺织服装",
        "综合",
        "职业教育",
        "能源",
        "航天军工",
        "航空航天",
        "航空运输",
        "营销",
        "视听器材",
        "计算机",
        "计算机应用",
        "计算机设备",
        "证券",
        "贵金属",
        "贸易",
        "路桥",
        "轻工制造",
        "运输设备",
        "通信",
        "通信服务",
        "通信设备制造",
        "通信运营",
        "通用机械",
        "造纸",
        "酒店",
        "金融",
        "钢铁",
        "铁路运输",
        "银行",
        "陶瓷",
        "零售",
        "食品",
        "食品饮料",
        "餐饮",
        "饮料",
        "饲料",
        "高等教育",
    ]
)


def get_app_key() -> str:
    """从环境变量读取 HTSC_APP_KEY，兼容 OpenClaw 等 Agent 运行环境"""
    # 尝试多种常见环境变量来源
    key = os.environ.get(ENV_KEY_NAME)
    if key:
        return key

    # 尝试从 .env 文件读取（OpenClaw 等工具常用方式）
    env_file_paths = [
        ".env",
        ".env.local",
        os.path.join(os.path.expanduser("~"), ".env"),
    ]
    for env_path in env_file_paths:
        if os.path.isfile(env_path):
            try:
                with open(env_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith(f"{ENV_KEY_NAME}="):
                            key = line.split("=", 1)[1].strip().strip('"').strip("'")
                            if key:
                                return key
            except Exception:
                continue

    # 尝试从上级目录的 .env 文件读取（适用于 skill 作为子目录的场景）
    current_dir = os.path.dirname(os.path.abspath(__file__))
    for _ in range(3):  # 向上回溯最多3层
        parent_env = os.path.join(current_dir, ".env")
        if os.path.isfile(parent_env):
            try:
                with open(parent_env, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith(f"{ENV_KEY_NAME}="):
                            key = line.split("=", 1)[1].strip().strip('"').strip("'")
                            if key:
                                return key
            except Exception:
                pass
        current_dir = os.path.dirname(current_dir)

    raise RuntimeError(
        f"未识别到您的 {ENV_KEY_NAME}，请前往行知 App 或行知网页版，进入“华泰智研 Skill 及 MCP 专区”，点击“API KEY”查看并复制您的专属认证码。\n\n"
        f"获取到认证码后，可通过以下任一方式配置（选择其一）：\n"
        f"  - 环境变量：export {ENV_KEY_NAME}=your_app_key\n"
        f"  - .env 文件：在项目根目录或 skill 同级目录创建 .env 文件，写入 {ENV_KEY_NAME}=your_app_key\n"
        f"  - .claude/settings.json：添加 \"env\": {{ \"{ENV_KEY_NAME}\": \"your_app_key\" }}"
    )


def validate_rank_changes(rank_changes: Optional[str]) -> None:
    """校验评级变动取值是否合法"""
    if rank_changes is None:
        return
    if rank_changes not in VALID_RANK_CHANGES:
        raise RuntimeError(
            f"评级变动参数 rankChanges 只能为以下值之一：首评、上调、下调、维持。"
            f"当前传入值为：\"{rank_changes}\"，请核对后重新输入。"
        )


def validate_macro_research(macro_research: Optional[str]) -> None:
    """校验总量研究方向取值是否合法"""
    if macro_research is None:
        return
    if macro_research not in VALID_MACRO_RESEARCH:
        raise RuntimeError(
            f"总量研究方向参数 macroResearch 只能为以下值之一：宏观、固定收益、策略、金工。"
            f"当前传入值为：\"{macro_research}\"，请核对后重新输入。"
        )


def validate_strategic_research(strategic_research: Optional[str]) -> None:
    """校验战略研究细分类型取值是否合法"""
    if strategic_research is None:
        return
    if strategic_research not in VALID_STRATEGIC_RESEARCH:
        raise RuntimeError(
            f"战略研究细分类型参数 strategicResearch 只能为以下值之一：经济政策与国际关系、能源转型、先进制造战略。"
            f"当前传入值为：\"{strategic_research}\"，请核对后重新输入。"
        )


def validate_industries(indu_name_list: Optional[List[str]]) -> None:
    """校验行业名称是否属于华泰行业体系"""
    if not indu_name_list:
        return
    invalid = [name for name in indu_name_list if name not in VALID_INDUSTRIES]
    if invalid:
        valid_list = "\n".join(f"  - {name}" for name in sorted(VALID_INDUSTRIES))
        raise RuntimeError(
            f"以下行业名称不属于华泰行业体系，请核对后重新输入：{invalid}\n\n"
            f"华泰行业体系完整行业名称列表如下（共 {len(VALID_INDUSTRIES)} 个）：\n{valid_list}"
        )


def build_payload(
    indu_name_list: Optional[List[str]] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    rank_changes: Optional[str] = None,
    initiated_tag: Optional[str] = None,
    author_name: Optional[str] = None,
    secu_abbr: Optional[str] = None,
    key_word: Optional[str] = None,
    macro_research: Optional[str] = None,
    strategic_research: Optional[str] = None,
) -> dict:
    """构建请求体"""
    params: dict = {"resource": "getLatestFiveReports"}

    if indu_name_list is not None:
        params["induNameList"] = indu_name_list
    if start_time is not None:
        params["startTime"] = start_time
    if end_time is not None:
        params["endTime"] = end_time
    if rank_changes is not None:
        params["rankChanges"] = rank_changes
    if initiated_tag is not None:
        params["initiatedTag"] = initiated_tag
    if author_name is not None:
        params["authorName"] = author_name
    if secu_abbr is not None:
        params["secuAbbr"] = secu_abbr
    if key_word is not None:
        params["keyWord"] = key_word
    if macro_research is not None:
        params["macroResearch"] = macro_research
    if strategic_research is not None:
        params["strategicResearch"] = strategic_research

    return {
        "channel": "ris",
        "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
        "method": "SkillCommonApi",
        "skillName": "htsc-report-skill",
        "params": params,
    }


def send_request(payload: dict, app_key: str) -> dict:
    """发送 POST 请求并返回 JSON 响应"""
    headers = {
        "Authorization": app_key,
        "Content-Type": "application/json",
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(API_URL, data=data, headers=headers, method="POST")

    try:
        with urlopen(req, timeout=30) as resp:
            resp_body = resp.read().decode("utf-8")
            return json.loads(resp_body)
    except HTTPError as e:
        raise RuntimeError(f"HTTP 错误: {e.code} {e.reason}") from e
    except URLError as e:
        raise RuntimeError(f"网络请求失败: {e.reason}") from e
    except json.JSONDecodeError as e:
        raise RuntimeError(f"响应解析失败: {e}") from e


def format_report(report: dict, index: int) -> str:
    """格式化单篇研报输出，确保所有字段完整返回不被截断"""
    title = report.get("showTitle", "未知标题")
    authors = report.get("authorNames") or "未知作者"
    pubdate = report.get("pubdate", "未知时间")
    summary = report.get("summay", "")

    # 处理摘要中的转义字符，保留完整内容
    if summary:
        summary = summary.replace("\\n", "\n").replace("\\t", "\t").strip()

    lines = [
        f"【{index}】{title}",
        f"    作者: {authors}",
        f"    发布时间: {pubdate}",
    ]
    if summary:
        lines.append(f"    摘要: {summary}")
    lines.append("")
    return "\n".join(lines)


def format_result(data: dict, filter_desc: str = "") -> str:
    """格式化查询结果"""
    code = data.get("code")
    msg = data.get("msg", "")

    if code != "0":
        return f"查询失败 (code={code}): {msg}"

    result_data = data.get("resultData", [])
    if not result_data:
        return "未找到符合条件的研报。"

    lines = ["数据来源：华泰证券研究所\n"]
    if filter_desc:
        lines.append(f"查询条件: {filter_desc}")
    lines.append(f"共返回 {len(result_data)} 篇研报（最多5篇）：\n")

    for i, report in enumerate(result_data, start=1):
        lines.append(format_report(report, i))

    lines.append("若您需查询更多研报，请登录华泰证券行知APP查看完整的专业研究分析。")
    lines.append("")
    lines.append(
        "【风险揭示】以上内容由 AI 基于华泰证券研究报告及其附属成果总结生成，"
        "可能省略完整报告中的重要信息、市场风险、业绩不及预期等风险，请务必阅读完整原始报告。"
        "有关数据、观点、评级等具有时效性，请自行核实最新信息。"
        "以上内容仅供研究学习使用，不构成任何投资建议。请勿二次传播并自行承担投资风险。"
    )

    return "\n".join(lines)


def fetch_reports(
    indu_name_list: Optional[List[str]] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    rank_changes: Optional[str] = None,
    initiated_tag: Optional[str] = None,
    author_name: Optional[str] = None,
    secu_abbr: Optional[str] = None,
    key_word: Optional[str] = None,
    macro_research: Optional[str] = None,
    strategic_research: Optional[str] = None,
) -> str:
    """
    查询华泰研报的主函数
    返回格式化后的结果字符串
    """
    validate_industries(indu_name_list)
    validate_rank_changes(rank_changes)
    validate_macro_research(macro_research)
    validate_strategic_research(strategic_research)
    app_key = get_app_key()
    payload = build_payload(
        indu_name_list=indu_name_list,
        start_time=start_time,
        end_time=end_time,
        rank_changes=rank_changes,
        initiated_tag=initiated_tag,
        author_name=author_name,
        secu_abbr=secu_abbr,
        key_word=key_word,
        macro_research=macro_research,
        strategic_research=strategic_research,
    )
    response = send_request(payload, app_key)

    # 构建筛选条件描述
    filters = []
    if indu_name_list:
        filters.append(f"行业={indu_name_list}")
    if start_time and end_time:
        filters.append(f"时间范围={start_time} 至 {end_time}")
    if rank_changes:
        filters.append(f"评级变动={rank_changes}")
    if initiated_tag:
        filters.append(f"首次覆盖={initiated_tag}")
    if author_name:
        filters.append(f"作者={author_name}")
    if secu_abbr:
        filters.append(f"证券简称={secu_abbr}")
    if key_word:
        filters.append(f"关键词={key_word}")
    if macro_research:
        filters.append(f"总量研究方向={macro_research}")
    if strategic_research:
        filters.append(f"战略研究细分类型={strategic_research}")
    filter_desc = "; ".join(filters) if filters else "无筛选条件"

    return format_result(response, filter_desc)


def main():
    parser = argparse.ArgumentParser(description="华泰证券研报查询工具")
    parser.add_argument("--industry", nargs="+", help="行业名称列表，可多个")
    parser.add_argument("--start-time", help="起始日期 yyyy-MM-dd")
    parser.add_argument("--end-time", help="结束日期 yyyy-MM-dd")
    parser.add_argument("--rank-changes", choices=["首评", "上调", "下调", "维持"], help="评级变动")
    parser.add_argument("--initiated-tag", choices=["是", "否"], help="是否首次覆盖")
    parser.add_argument("--author", help="作者姓名（模糊匹配）")
    parser.add_argument("--secu-abbr", help="证券简称（模糊匹配）")
    parser.add_argument("--keyword", help="关键词（模糊匹配）")
    parser.add_argument(
        "--macro-research",
        choices=["宏观", "固定收益", "策略", "金工"],
        help="总量研究方向：宏观、固定收益、策略、金工",
    )
    parser.add_argument(
        "--strategic-research",
        choices=["经济政策与国际关系", "能源转型", "先进制造战略"],
        help="战略研究细分类型：经济政策与国际关系、能源转型、先进制造战略",
    )

    args = parser.parse_args()

    # 校验时间范围必须同时传入
    if (args.start_time and not args.end_time) or (not args.start_time and args.end_time):
        parser.error("--start-time 和 --end-time 必须同时传入或同时不传")

    try:
        result = fetch_reports(
            indu_name_list=args.industry,
            start_time=args.start_time,
            end_time=args.end_time,
            rank_changes=args.rank_changes,
            initiated_tag=args.initiated_tag,
            author_name=args.author,
            secu_abbr=args.secu_abbr,
            key_word=args.keyword,
            macro_research=args.macro_research,
            strategic_research=args.strategic_research,
        )
        print(result)
    except RuntimeError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
