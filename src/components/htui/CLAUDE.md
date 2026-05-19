# components/htui/ — 金融可视化组件（14 个）

后端通过 artifact block 传递结构化 JSON，前端 ArtifactRenderer 分发到对应组件渲染。

## 统一接口协议

- 后端产出格式：` ```artifact:TYPE\n{json data}\n``` `
- ArtifactRenderer.tsx 根据 TYPE 分发到对应组件
- 每个组件接收 `{ data: T }` prop，T 为该组件的数据类型
- 组件必须处理 data 为空/格式异常（不 crash，显示 fallback）

## 组件清单

| 组件 | 目录/文件 | 渲染引擎 | 数据来源 | 稳定度 |
|------|-----------|---------|---------|--------|
| QuoteCard | QuoteCard/QuoteCard.tsx | React | westock-quote | 🔒 |
| KLineChart | KLineChart/KLineChart.tsx | Lightweight Charts v5 | westock-quote | 🔒 |
| BarChart | BarChart/BarChart.tsx | ECharts 6 | 多技能 | 🔒 |
| LineChart | LineChart/LineChart.tsx | ECharts 6 | 多技能 | 🔒 |
| DataTable | DataTable/DataTable.tsx | Ant Design Table | 多技能 | 🔒 |
| NewsCard | NewsCard/NewsCard.tsx | React | westock-research / 新闻搜索 | 🔒 |
| NewsFeed | NewsFeed/NewsFeed.tsx | React | 新闻搜索 | 🔧 |
| AIHotNews | AIHotNews/AIHotNews.tsx | React | web-access | 🔧 |
| FinanceBreakfast | FinanceBreakfast/FinanceBreakfast.tsx | React | cron 推送 | 🔧 |
| StockSnapshot | StockSnapshot/StockSnapshot.tsx | React + SVG | westock-quote | 🔒 |
| SectorHeatmap | SectorHeatmap/SectorHeatmap.tsx | ECharts Treemap | westock-market | 🔒 |
| ResearchConsensus | ResearchConsensus/ResearchConsensus.tsx | React | westock-research | 🔒 |
| FinancialHealth | FinancialHealth/FinancialHealth.tsx | React | 财务数据查询 | 🔒 |

核心分发文件：`ArtifactRenderer.tsx`（COMPONENT_MAP 注册表）

## 新增组件步骤

1. 在 `htui/` 下创建 `NewComponent/NewComponent.tsx`
2. 导出 default 组件，接收 `{ data: YourDataType }` prop
3. 在 `ArtifactRenderer.tsx` 的 COMPONENT_MAP 中注册 `'type-name': NewComponent`
4. 在后端 `src-api/.../codeany/index.ts` 的 `ARTIFACT_TYPE_MAP` 注册映射
5. 在 `src-api/resources/defaults/AGENTS.md` 的 artifact 协议段添加使用示例

## 不变量

- 组件内**不发 API 请求**，数据完全由后端 artifact 传入
- ECharts 组件必须支持 resize 和 dispose（防内存泄漏）
- 不用 `React.lazy()`，全部静态 import（防闪烁）
- 组件必须有 loading/error/empty 三态处理
- 图表组件必须支持黑色/白色/浅黄三种主题色
