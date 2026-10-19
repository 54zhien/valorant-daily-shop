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
// ============================================================================

struct RolePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.availableRoles, id: \.identityKey) { role in
                        row(role)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(ZWBrandBackdrop())
            .navigationTitle("切换角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ role: UserRole) -> some View {
        let selected = role.identityKey == model.userRole?.identityKey
        return Button {
            model.selectRole(role)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                avatar(role)

                VStack(alignment: .leading, spacing: 3) {
                    Text(role.displayName)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(subtitle(role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.zwMint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.zwMint.opacity(0.18)) : .regular,
                     in: .rect(cornerRadius: 16))
    }

    private func avatar(_ role: UserRole) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.12))
            if !role.icon.isEmpty, let url = URL(string: role.icon) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initial(role)
                    }
                }
            } else {
                initial(role)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
    }

    private func initial(_ role: UserRole) -> some View {
        Text(String(role.displayName.prefix(1)))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
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
