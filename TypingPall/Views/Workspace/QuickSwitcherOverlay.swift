import SwiftUI

struct QuickSwitcherOverlay: View {
    @Binding var isPresented: Bool
    let lessons: [PracticeLesson]
    let onSelect: (PracticeLesson) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    init(isPresented: Binding<Bool>, lessons: [PracticeLesson], onSelect: @escaping (PracticeLesson) -> Void) {
        self._isPresented = isPresented
        self.lessons = lessons
        self.onSelect = onSelect
    }

    private var filteredLessons: [PracticeLesson] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Array(lessons.prefix(12)) }
        return Array(lessons.filter { lesson in
            lesson.title.localizedCaseInsensitiveContains(trimmed) ||
            lesson.language.title.localizedCaseInsensitiveContains(trimmed) ||
            lesson.category.localizedCaseInsensitiveContains(trimmed) ||
            (lesson.triggers?.contains { $0.localizedCaseInsensitiveContains(trimmed) } ?? false) ||
            (lesson.mantra?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }.prefix(12))
    }

    public var body: some View {
        if isPresented {
            ZStack(alignment: .top) {
                // Dimmed backdrop
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        isPresented = false
                    }

                // Floating Palette Pill
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("Type a pattern name, language, cue, or keyword…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($isFieldFocused)
                            .accessibilityIdentifier("quickSwitcherSearch")
                            .onSubmit {
                                if !filteredLessons.isEmpty && selectedIndex < filteredLessons.count {
                                    let chosen = filteredLessons[selectedIndex]
                                    onSelect(chosen)
                                    isPresented = false
                                }
                            }

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("esc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.14))
                            .cornerRadius(4)
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

                    Divider()

                    // Results List
                    if filteredLessons.isEmpty {
                        VStack(spacing: 6) {
                            Text("No patterns match “\(query)”")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(Array(filteredLessons.enumerated()), id: \.element.id) { index, lesson in
                                Button {
                                    onSelect(lesson)
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        TriRingMasteryGlyph(level: MasteryStore.shared.level(for: lesson.id), size: 14)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lesson.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)

                                            HStack(spacing: 6) {
                                                Text(lesson.category)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text("·")
                                                    .foregroundColor(.secondary)
                                                Text(lesson.language.title)
                                                    .font(.caption2)
                                                    .foregroundColor(Color.accentColor)
                                            }
                                        }

                                        Spacer()

                                        if index == selectedIndex {
                                            Text("↵")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(index == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(width: 580)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(TypingPalette.subtleBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
                .padding(.top, 70)
            }
            .onAppear {
                isFieldFocused = true
                selectedIndex = 0
            }
        }
    }
}
