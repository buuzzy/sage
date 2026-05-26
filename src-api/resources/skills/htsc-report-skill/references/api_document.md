# 华泰证券研究所研报接口文档

## 接口概述

本接口用于按照筛选条件获取**华泰证券研究所**发布的最新五篇研报。所有返回的研报数据均来源于华泰证券研究所，研报观点、评级及摘要内容均为华泰证券研究团队的独立研究成果。

| 项目 | 说明 |
|------|------|
| 接口地址 | `https://inst.htsc.com/institution/skill/tool/apiGateway` |
| 请求方式 | POST |
| 认证方式 | Header 中携带 `Authorization: HTSC_APP_KEY` |

---

## 请求头

| 字段名 | 必填 | 说明 |
|--------|------|------|
| Authorization | 是 | 环境变量 `HTSC_APP_KEY` 的值 |
| Content-Type | 是 | `application/json` |

---

## 请求体

### 固定入参

以下字段为固定值，不可修改：

| 字段名 | 类型 | 固定值 | 说明 |
|--------|------|--------|------|
| channel | string | `"ris"` | 渠道标识 |
| serviceName | string | `"com.htsc.ris.out.api.RisOutSkillServiceI"` | 服务名称 |
| method | string | `"SkillCommonApi"` | 方法名称 |
| skillName | string | `"htsc-report-skill"` | 技能名称 |
| params.resource | string | `"getLatestFiveReports"` | 资源标识 |

### 业务参数（params 对象）

| 字段名 | 类型 | 必填 | 说明 | 示例值 |
|--------|------|------|------|--------|
| resource | string | 是 | 资源标识（固定值） | `"getLatestFiveReports"` |
| induNameList | array[string] | 否 | 行业名称列表，支持多选。**仅支持华泰行业体系**，不支持申万、中信等其他行业体系。若传入无效名称，接口将返回错误并附带完整行业列表 | `["必选消费", "能源"]` |
| startTime | string | 否 | 起始日期，格式 `yyyy-MM-dd` | `"2025-01-01"` |
| endTime | string | 否 | 结束日期，格式 `yyyy-MM-dd` | `"2025-10-13"` |
| rankChanges | string | 否 | 评级变动，可选值：`"首评"`、`"上调"`、`"下调"`、`"维持"` | `"上调"` |
| initiatedTag | string | 否 | 是否首次覆盖，可选值：`"是"`、`"否"` | `"是"` |
| authorName | string | 否 | 作者姓名，支持模糊匹配 | `""` |
| secuAbbr | string | 否 | 证券简称，支持模糊匹配 | `"平安银行"` |
| keyWord | string | 否 | 关键词，支持模糊匹配 | `"量子计算"` |
| macroResearch | string | 否 | 总量研究方向，可选值：`"宏观"`、`"固定收益"`、`"策略"`、`"金工"` | `"宏观"` |
| strategicResearch | string | 否 | 战略研究细分类型，可选值：`"经济政策与国际关系"`、`"能源转型"`、`"先进制造战略"` | `"经济政策与国际关系"` |

### 请求示例

```json
{
    "channel": "ris",
    "serviceName": "com.htsc.ris.out.api.RisOutSkillServiceI",
    "method": "SkillCommonApi",
    "skillName": "htsc-report-skill",
    "params": {
        "resource": "getLatestFiveReports",
        "induNameList": ["必选消费", "能源"],
        "startTime": "2025-01-01",
        "endTime": "2025-10-13",
        "rankChanges": "上调",
        "initiatedTag": "是",
        "authorName": "",
        "secuAbbr": "平安银行",
        "keyWord": "量子计算",
        "macroResearch": "宏观",
        "strategicResearch": "经济政策与国际关系"
    }
}
```

---

## 响应体

### 响应字段说明

| 字段名 | 类型 | 说明 |
|--------|------|------|
| code | string | 响应码，`"0"` 表示成功 |
| msg | string | 响应消息，`"success"` 表示成功 |
| resultData | array[object] | 研报列表，最多返回 5 篇 |

### resultData 数组元素字段

| 字段名 | 类型 | 说明 |
|--------|------|------|
| showTitle | string | 研报标题，包含股票代码、简称及评级 |
| authorNames | string \| null | 作者姓名，可能为 null |
| summay | string | 研报摘要内容（含换行符和制表符） |
| pubdate | string | 发布时间，格式 `yyyy-MM-dd HH:mm:ss` |

### 响应示例

```json
{
    "code": "0",
    "msg": "success",
    "resultData": [
        {
            "showTitle": "宁德时代(3750 HK,买入): 全球电气化的"心脏"",
            "authorNames": "边文姣",
            "summay": "\n\t\t我们和市场的不同：...",
            "pubdate": "2026-05-09 13:40:30"
        },
        {
            "showTitle": "电力设备与新能源: 能源转型新技术观察（6）：太空光伏，是否会成为下一个星辰大海？",
            "authorNames": "刘俊",
            "summay": "\n\t\t近日我国一次性向国际通信联盟提交了超20万颗卫星的部署计划...",
            "pubdate": "2026-05-09 13:40:30"
        }
    ]
}
```

---

## 响应码说明

| code | 说明 |
|------|------|
| "0" | 请求成功 |
| 其他 | 请求失败，详见 msg 字段描述 |

---

## 注意事项

1. **环境变量依赖**：`HTSC_APP_KEY` 需通过环境变量配置，不可硬编码。
2. **行业名称限制**：`induNameList` 只能接收华泰行业体系的行业名称（共 159 个），不支持申万、中信等其他行业体系。若传入无效名称，脚本会返回错误提示并列出所有有效行业名称。
3. **评级变动限制**：`rankChanges` 只能为 `"首评"`、`"上调"`、`"下调"`、`"维持"` 之一，传入其他值将报错。
4. **总量研究方向限制**：`macroResearch` 只能为 `"宏观"`、`"固定收益"`、`"策略"`、`"金工"` 之一，传入其他值将报错。
5. **战略研究细分类型限制**：`strategicResearch` 只能为 `"经济政策与国际关系"`、`"能源转型"`、`"先进制造战略"` 之一，传入其他值将报错。
5. **返回数量限制**：该接口固定返回最新的 5 篇研报，不可通过参数调整数量。
6. **摘要格式**：`summay` 字段中包含 `\n`（换行）和 `\t`（制表符）等转义字符，使用前需进行转义处理。
5. **作者可能为空**：`authorNames` 字段可能返回 `null`，调用方需做好空值兼容。
6. **时间范围**：`startTime` 和 `endTime` 需同时传入或同时不传，建议保持日期格式统一为 `yyyy-MM-dd`。
7. **数据完整性**：接口返回的研报数据（包括标题、作者、发布时间、摘要等全部字段）必须完整呈现，不得截断或省略。摘要字段 `summay` 可能包含较长文本，调用方需确保完整输出。
