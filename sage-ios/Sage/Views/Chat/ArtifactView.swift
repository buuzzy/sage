import SwiftUI
import WebKit

/// Artifact 渲染视图 — K 线图使用 Swift Charts 原生渲染，其他类型用 WKWebView + ECharts
/// 支持的类型：kline-chart, bar-chart, line-chart, quote-card, data-table 等
struct ArtifactView: View {
    let type: String
    let jsonData: String
    @State private var showFullScreen = false

    var body: some View {
        // K 线图走 Swift Charts 原生渲染
        if type == "kline-chart", let chartData = parseKLineData(jsonData) {
            Button {
                showFullScreen = true
            } label: {
                VStack(alignment: .leading, spacing: SageTheme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artifactTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("点击全屏查看")
                                .font(.system(size: 12))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SageTheme.ColorToken.brand)
                            .frame(width: 30, height: 30)
                            .background(SageTheme.ColorToken.brandSoft)
                            .clipShape(Circle())
                    }

                    NativeKLineChartView(data: chartData, compact: true)
                        .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
                }
                .padding(SageTheme.Spacing.sm)
                .sageSoftCard(cornerRadius: SageTheme.Radius.lg)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showFullScreen) {
                NativeKLineFullScreenView(data: chartData)
            }
        } else {
            // 其他 artifact 类型保留 WebView 渲染
            Button {
                showFullScreen = true
            } label: {
                VStack(alignment: .leading, spacing: SageTheme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artifactTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("点击全屏查看")
                                .font(.system(size: 12))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SageTheme.ColorToken.brand)
                            .frame(width: 30, height: 30)
                            .background(SageTheme.ColorToken.brandSoft)
                            .clipShape(Circle())
                    }

                    ArtifactWebView(type: type, jsonData: jsonData)
                        .frame(height: compactHeight)
                        .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
                }
                .padding(SageTheme.Spacing.sm)
                .sageSoftCard(cornerRadius: SageTheme.Radius.lg)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showFullScreen) {
                ArtifactFullScreenView(type: type, title: artifactTitle, jsonData: jsonData)
            }
        }
    }

    /// 解析 K 线 JSON 数据
    private func parseKLineData(_ json: String) -> KLineChartData? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KLineChartData.self, from: data)
    }

    private var compactHeight: CGFloat {
        switch type {
        case "quote-card": return 132
        case "stock-snapshot": return 160
        default: return 220
        }
    }

    private var artifactTitle: String {
        switch type {
        case "quote-card": return "行情卡片"
        case "kline-chart": return "K 线图"
        case "bar-chart": return "柱状图"
        case "line-chart": return "趋势图"
        case "data-table": return "数据表"
        case "stock-snapshot": return "股票快照"
        case "sector-heatmap": return "板块热力图"
        case "research-consensus": return "研报共识"
        case "financial-health": return "财务健康"
        case "news-feed", "news-list": return "资讯流"
        default: return "金融图表"
        }
    }
}

struct ArtifactFullScreenView: View {
    let type: String
    let title: String
    let jsonData: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArtifactWebView(type: type, jsonData: jsonData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(SageTheme.ColorToken.surfaceSecondary)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}

/// WKWebView 包装 — 加载 ECharts HTML
struct ArtifactWebView: UIViewRepresentable {
    let type: String
    let jsonData: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(type: type, data: jsonData)
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// 生成 ECharts HTML
    private func generateHTML(type: String, data: String) -> String {
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let bgColor = isDark ? "#1c1c1e" : "#ffffff"
        let textColor = isDark ? "#e5e5e5" : "#333333"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; background: \(bgColor); overflow: hidden; }
                #chart { width: 100%; height: 100%; }
                .card { padding: 16px; font-family: -apple-system, system-ui, sans-serif; color: \(textColor); }
                .card-title { font-size: 14px; font-weight: 600; margin-bottom: 8px; }
                .card-value { font-size: 24px; font-weight: 700; }
                .card-change { font-size: 13px; margin-top: 4px; }
                .positive { color: #ef4444; }
                .negative { color: #22c55e; }
                table { width: 100%; border-collapse: collapse; font-size: 13px; color: \(textColor); }
                th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid \(isDark ? "#333" : "#eee"); }
                th { font-weight: 600; background: \(isDark ? "#2c2c2e" : "#f9f9f9"); }
            </style>
        </head>
        <body>
            <div id="chart"></div>
            <script>
                try {
                    const type = '\(type)';
                    const data = \(data);
                    const isDark = \(isDark ? "true" : "false");

                    if (type === 'quote-card') {
                        renderQuoteCard(data);
                    } else if (type === 'data-table') {
                        renderDataTable(data);
                    } else {
                        renderEChart(type, data, isDark);
                    }

                    function renderQuoteCard(d) {
                        const el = document.getElementById('chart');
                        const change = d.change || 0;
                        const changePercent = d.changePercent || 0;
                        const cls = change >= 0 ? 'positive' : 'negative';
                        const sign = change >= 0 ? '+' : '';
                        el.innerHTML = `
                            <div class="card">
                                <div class="card-title">${d.name || d.symbol || ''}</div>
                                <div class="card-value">${d.price || d.close || '-'}</div>
                                <div class="card-change ${cls}">${sign}${change} (${sign}${changePercent}%)</div>
                            </div>
                        `;
                    }

                    function renderDataTable(d) {
                        const el = document.getElementById('chart');
                        const cols = d.columns || [];
                        const rows = d.rows || d.data || [];
                        let html = '<table><thead><tr>';
                        cols.forEach(c => { html += `<th>${c.label || c.key || c}</th>`; });
                        html += '</tr></thead><tbody>';
                        rows.forEach(row => {
                            html += '<tr>';
                            cols.forEach(c => {
                                const key = c.key || c;
                                html += `<td>${row[key] ?? ''}</td>`;
                            });
                            html += '</tr>';
                        });
                        html += '</tbody></table>';
                        el.innerHTML = html;
                    }

                    function renderEChart(type, data, isDark) {
                        const chart = echarts.init(document.getElementById('chart'), isDark ? 'dark' : null);
                        let option = {};

                        if (type === 'kline-chart') {
                            const kData = data.klines || data.data || [];
                            const dates = kData.map(k => k.time || k.date || k[0]);
                            const values = kData.map(k => [k.open || k[1], k.close || k[2], k.low || k[3], k.high || k[4]]);
                            option = {
                                backgroundColor: 'transparent',
                                grid: { top: 30, right: 10, bottom: 30, left: 50 },
                                xAxis: { type: 'category', data: dates, axisLabel: { fontSize: 10 } },
                                yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
                                series: [{ type: 'candlestick', data: values }]
                            };
                        } else if (type === 'bar-chart') {
                            const labels = (data.data || data.items || []).map(d => d.name || d.label || '');
                            const values = (data.data || data.items || []).map(d => d.value || 0);
                            option = {
                                backgroundColor: 'transparent',
                                grid: { top: 20, right: 10, bottom: 40, left: 50 },
                                xAxis: { type: 'category', data: labels, axisLabel: { fontSize: 10, rotate: 30 } },
                                yAxis: { type: 'value', axisLabel: { fontSize: 10 } },
                                series: [{ type: 'bar', data: values, itemStyle: { borderRadius: [4, 4, 0, 0] } }]
                            };
                        } else if (type === 'line-chart') {
                            const labels = (data.data || data.items || []).map(d => d.date || d.name || '');
                            const values = (data.data || data.items || []).map(d => d.value || d.close || 0);
                            option = {
                                backgroundColor: 'transparent',
                                grid: { top: 20, right: 10, bottom: 30, left: 50 },
                                xAxis: { type: 'category', data: labels, axisLabel: { fontSize: 10 } },
                                yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
                                series: [{ type: 'line', data: values, smooth: true, areaStyle: { opacity: 0.1 } }]
                            };
                        } else {
                            // Fallback: show raw JSON
                            document.getElementById('chart').innerHTML = '<pre style="padding:12px;font-size:11px;overflow:auto;color:\\(textColor)">' + JSON.stringify(data, null, 2) + '</pre>';
                            return;
                        }

                        chart.setOption(option);
                        window.addEventListener('resize', () => chart.resize());
                    }
                } catch(e) {
                    document.getElementById('chart').innerHTML = '<div class="card"><div class="card-title">渲染错误</div><div style="font-size:12px;color:#999">' + e.message + '</div></div>';
                }
            </script>
        </body>
        </html>
        """;
    }
}
