import SwiftUI

/// 清理和项目产物共用的删除进度：当前项、比例、已处理大小、已完成的行。
struct DeleteProgressPanel: View {
    var progress: CleanDeleteProgress?
    var title: String
    var doneTitle: String

    var body: some View {
        let completed = progress?.completed ?? 0
        let total = progress?.total ?? 0
        let freed = progress?.freedBytes ?? 0
        return FillColumn(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(completed) / \(total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress?.fraction ?? 0)
            Text("\(doneTitle) \(CleanPlan.decimalLabel(freed))")
                .font(.title3.monospacedDigit())
            if let current = progress?.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(current.name)
                        .lineLimit(1)
                    Text(Format.homeAbbreviated(current.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !current.group.isEmpty {
                        Text(current.group)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if completed == 0 {
                Text("正在准备。")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(progress?.done ?? []) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: row.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(row.ok ? Color(red: 0.18, green: 0.70, blue: 0.42) : Theme.danger)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.item.name)
                                    .lineLimit(1)
                                Text(row.ok ? Format.homeAbbreviated(row.item.path) : row.message)
                                    .font(.caption)
                                    .foregroundStyle(row.ok ? .secondary : Theme.danger)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(row.item.bytes.map { CleanPlan.decimalLabel($0) } ?? "")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
}
