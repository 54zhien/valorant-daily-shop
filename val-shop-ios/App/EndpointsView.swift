import SwiftUI
import ZhangwaKit

/// 抓包文件里出现的全部 `/go/` 接口 —— 一眼找到商店那条。
///
/// 只出现在**诊断台**里（普通用户的界面上没有），由父级 NavigationStack 推入。
/// 用系统的 `List` + `.searchable` + toolbar 上的筛选开关 —— 都是文档里的做法。
struct EndpointsView: View {

    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var onlyStore = true

    private var list: [CaptureImporter.Endpoint] {
        model.endpoints
            .filter { onlyStore ? $0.looksLikeStore : true }
            .filter { query.isEmpty ? true : $0.url.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if model.endpoints.isEmpty {
                ContentUnavailableView {
                    Label("还没有接口列表", systemImage: "tray")
                } description: {
                    Text("到「动作 → 扫描 App 文件夹」导入一份 mval_capture.log，这里就会列出抓到的所有 /go/ 接口。")
                }
            } else if list.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(list) { endpoint in
                    row(endpoint)
                }
            }
        }
        .navigationTitle("抓到的接口")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索路径")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $onlyStore) {
                    Label("只看商店", systemImage: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
            }
        }
    }

    private func row(_ endpoint: CaptureImporter.Endpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(endpoint.methods.joined(separator: "/"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if endpoint.looksLikeStore {
                    Text("疑似商店")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.zwSignal)
                }
                Spacer(minLength: 0)
            }

            Text(endpoint.url)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let body = endpoint.sampleBody, !body.isEmpty {
                Text("body  \(body)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let resp = endpoint.sampleResponse, !resp.isEmpty {
                Text("resp  \(resp)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            Button("设为商店接口") {
                model.setShopPath(fromEndpoint: endpoint.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
