import SwiftUI
import ZhangwaKit

// ============================================================================
//  角色切换
// ============================================================================
//
//  只在有**多个**可切换角色时才出现（`model.canSwitchRole`）——
//  一个人只有一个号的时候，弹个只有一个选项的列表纯属打扰。
//
//  列的是 `gameRoles.selectableRoles`，只含端游角色：
//  这个 App 看的是端游每日商店，切到手游角色会让人以为商店数据会跟着变。
//
//  用系统的 `List` + 勾选行，不做自绘卡片。
// ============================================================================

struct RolePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.availableRoles, id: \.identityKey) { role in
                Button {
                    model.selectRole(role)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        avatar(role)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(role.displayName)
                                .font(.subheadline.weight(isSelected(role) ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(subtitle(role))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if isSelected(role) {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected(role) ? [.isSelected] : [])
            }
            .navigationTitle("切换角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func isSelected(_ role: UserRole) -> Bool {
        role.identityKey == model.userRole?.identityKey
    }

    private func avatar(_ role: UserRole) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            if !role.icon.isEmpty, let url = URL(string: role.icon) {
                CachedImage(url: url, contentMode: .fill) { initial(role) }
            } else {
                initial(role)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func initial(_ role: UserRole) -> some View {
        Text(String(role.displayName.prefix(1)))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
    }

    /// 段位 · 等级 · 大区
    private func subtitle(_ role: UserRole) -> String {
        var bits: [String] = []
        if !role.rankText.isEmpty { bits.append(role.rankText) }
        if role.level > 0 { bits.append("Lv\(role.level)") }
        if !role.areaName.isEmpty { bits.append(role.areaName) }
        if bits.isEmpty { bits.append(role.gameName.isEmpty ? role.platformText : role.gameName) }
        return bits.joined(separator: " · ")
    }
}
