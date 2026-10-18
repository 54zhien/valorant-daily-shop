import SwiftUI
import ZhangwaKit

/// 列出抓包文件里出现的全部 `/go/` 接口 —— 一眼找到商店那条。
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
        NavigationStack {
            Group {
                if model.endpoints.isEmpty {
                    ContentUnavailableView {
                        Label("还没有接口列表", systemImage: "tray")
                    } description: {
                        Text("到「设置」里导入一份 mval_capture.log，这里就会列出抓到的所有 /go/ 接口。")
                    }
                } else if list.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(list) { endpoint in
                                EndpointRow(endpoint: endpoint) {
                                    model.setShopPath(fromEndpoint: endpoint.url)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .zwScrollEdge(.all)
                }
            }
            .background(ZWBrandBackdrop())
            .navigationTitle("抓到的接口")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索路径")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $onlyStore) {
                        Label("只看商店", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }
}

private struct EndpointRow: View {
    let endpoint: CaptureImporter.Endpoint
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(endpoint.methods.joined(separator: "/"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.zwMint)
                if endpoint.looksLikeStore {
                    Text("疑似商店")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .zwGlassChip(tint: .orange)
                }
                Spacer(minLength: 0)
            }

            Text(endpoint.url)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)

            if let body = endpoint.sampleBody, !body.isEmpty {
                Text("body  \(body)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let resp = endpoint.sampleResponse, !resp.isEmpty {
                Text("resp  \(resp)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            Button(action: onUse) {
                Label("设为商店接口", systemImage: "checkmark.circle")
                    .font(.caption)
            }
            .zwGlassButton()
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zwGlassPanel(cornerRadius: 18)
    }
}
