import SwiftUI

/// 选择一个人物（用于合并 / 移动）
struct PersonPickerView: View {
    let title: String
    let people: [Person]
    var onPick: (Person) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if people.isEmpty {
                    Text("没有其他人物").foregroundColor(.secondary)
                } else {
                    ForEach(people) { person in
                        Button {
                            onPick(person)
                            dismiss()
                        } label: {
                            Text(person.displayName).foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
