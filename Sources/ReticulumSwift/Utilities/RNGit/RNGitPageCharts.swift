//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// The bar charts a statistics page is drawn with.
public enum RNGitPageCharts {

  /// What stands in for a chart there is nothing to draw.
  public static let noData = "No data available\n"

  /// How far a bar's gradient is run unless the caller says otherwise.
  public static let defaultGradientFactor = 1.3

  /// How much of the primary colour a bar's own dark end keeps.
  static let secondaryFraction = 0.42

  /// `data` drawn as one bar per point, each bar half a character wide in height.
  public static func chart(
    _ data: [Int], labels: [String], colour: String = "666", height: Int = 10,
    secondaryColour: String? = nil, gradientFactor: Double? = nil
  ) -> String {
    halfBlock(
      data, labels: labels, colour: colour, height: height, secondaryColour: secondaryColour,
      gradientFactor: gradientFactor)
  }

  /// `data` drawn as one bar per point, each row picking the shade its height calls for.
  public static func fullBlock(
    _ data: [Int], labels: [String], colour: String = "666", height: Int = 10
  ) -> String {
    guard !data.isEmpty, data.contains(where: { $0 != 0 }) else { return noData }
    let peak = Double(max(data.max() ?? 0, 1))

    var lines = ["`F\(colour)Peak: \(data.max() ?? 0)`f\n"]
    for row in stride(from: height, through: 1, by: -1) {
      let threshold = Double(row - 1) / Double(height) * peak
      var line = "\u{2502}"
      for value in data {
        guard Double(value) > threshold else {
          line += " "
          continue
        }
        let shade: String
        if Double(row) >= Double(height) * 0.875 {
          shade = "\u{2588}"
        } else if Double(row) >= Double(height) * 0.625 {
          shade = "\u{2593}"
        } else if Double(row) >= Double(height) * 0.375 {
          shade = "\u{2592}"
        } else {
          shade = "\u{2591}"
        }
        line += "`F\(colour)\(shade)`f"
      }
      lines.append(line + "\n")
    }

    lines.append(border(across: data.count))
    lines.append(labelLine(labels, across: data.count))
    return lines.joined()
  }

  /// `data` drawn as one bar per point, each character carrying an upper and a lower half.
  static func halfBlock(
    _ data: [Int], labels: [String], colour: String, height: Int, secondaryColour: String?,
    gradientFactor: Double?
  ) -> String {
    let factor = gradientFactor.flatMap { $0 == 0 ? nil : $0 } ?? defaultGradientFactor
    guard !data.isEmpty, data.contains(where: { $0 != 0 }) else { return noData }
    let peak = Double(max(data.max() ?? 0, 1))

    let primary = expanded(colour)
    let secondary =
      secondaryColour.map(expanded)
      ?? rgb(of: primary).map { String(format: "%02x", Int(Double($0) * secondaryFraction)) }
      .joined()
    let primaryRGB = rgb(of: primary)
    let secondaryRGB = rgb(of: secondary)

    func gradient(_ position: Double) -> String {
      (0..<3).map { index -> String in
        let from = Double(secondaryRGB[index])
        let to = Double(primaryRGB[index])
        return String(format: "%02x", Int(from + (to - from) * min(1, position * factor)))
      }.joined()
    }

    var lines = ["`FT\(primary)Peak: \(data.max() ?? 0)`f\n"]
    for row in stride(from: height, through: 1, by: -1) {
      let top = Double(row) / Double(height) * peak
      let bottom = Double(row - 1) / Double(height) * peak
      let middle = (top + bottom) / 2
      let gradientTop = gradient(Double(row) / Double(height))
      let gradientMiddle = gradient((Double(row) - 0.5) / Double(height))

      var line = "\u{2502}"
      for value in data {
        let upper = Double(value) >= top
        let lower = Double(value) >= middle || (row == 1 && value > 0)
        if !upper && !lower {
          line += " "
        } else if upper {
          line += "`FT\(gradientTop)`BT\(gradientMiddle)\u{2580}`f`b"
        } else {
          line += "`FT\(gradientMiddle)\u{2584}`f"
        }
      }
      lines.append(line + "\n")
    }

    lines.append(border(across: data.count))
    lines.append(labelLine(labels, across: data.count))
    return lines.joined()
  }

  /// The four counts a repository keeps, drawn as one stack of bars.
  public static func combined(
    views: [Int], fetches: [Int], pushes: [Int], downloads: [Int], labels: [String],
    height: Int = 6, colours: [Category: String]? = nil, dim: Double = 0.87
  ) -> String {
    guard !views.isEmpty, !fetches.isEmpty, !pushes.isEmpty, !downloads.isEmpty else {
      return noData
    }

    func shade(_ category: Category) -> String {
      dimmed(expanded(colours?[category] ?? category.colour), by: dim)
    }

    func counts(of category: Category) -> [Int] {
      switch category {
      case .pushes: return pushes
      case .fetches: return fetches
      case .views: return views
      case .downloads: return downloads
      }
    }

    let points = views.count
    let legend = Category.allCases.map {
      "`FT\(shade($0))`BT\(shade($0))\u{2588}\u{2588}`f`b \($0.name)"
    }.joined(separator: "  ")
    var lines = [legend + "\n\n"]

    for row in stride(from: height, through: 1, by: -1) {
      let lowerMinimum = (Double(row) - 1) / Double(height)
      let lowerMaximum = (Double(row) - 0.5) / Double(height)
      let upperMinimum = lowerMaximum
      let upperMaximum = Double(row) / Double(height)

      var line = "\u{2502}"
      for point in 0..<points {
        let total = Category.allCases.reduce(0) { $0 + counts(of: $1)[point] }
        guard total != 0 else {
          line += " "
          continue
        }

        var running = 0
        var spans: [(category: Category, start: Double, end: Double)] = []
        for category in Category.allCases {
          let start = Double(running) / Double(total)
          running += counts(of: category)[point]
          spans.append((category, start, Double(running) / Double(total)))
        }

        func category(from minimum: Double, to maximum: Double) -> Category? {
          spans.first { minimum < $0.end && maximum > $0.start }?.category
        }

        let upper = category(from: upperMinimum, to: upperMaximum)
        let lower = category(from: lowerMinimum, to: lowerMaximum)
        switch (upper, lower) {
        case (nil, nil):
          line += " "
        case (let upper?, let lower?) where upper == lower:
          line += "`FT\(shade(upper))`BT\(shade(upper))\u{2588}`f`b"
        case (let upper?, let lower?):
          line += "`FT\(shade(upper))`BT\(shade(lower))\u{2580}`f`b"
        case (let upper?, nil):
          line += "`FT\(shade(upper))\u{2580}`f"
        case (nil, let lower?):
          line += "`FT\(shade(lower))\u{2584}`f"
        }
      }
      lines.append(line + "\n")
    }

    let bottom = "\u{2514}" + String(repeating: "\u{2500}", count: points) + "\u{2518}"
    lines.append(bottom + "\n")

    if !labels.isEmpty {
      let first = String(labels[0].prefix(12))
      let last = String(labels[labels.count - 1].prefix(12))
      let middle = max(0, bottom.count - first.count - last.count)
      lines.append(
        RNGitPage.Colour.dim + first + String(repeating: " ", count: middle) + last + "`f\n")
    }

    return lines.joined()
  }

  /// What a stacked chart counts, in the order the stack is built from the bottom up.
  public enum Category: String, CaseIterable, Sendable {

    /// What a repository was pushed.
    case pushes
    /// What a repository was fetched.
    case fetches
    /// What a repository was looked at.
    case views
    /// What was taken out of a repository.
    case downloads

    /// The colour this category is drawn in.
    var colour: String {
      switch self {
      case .pushes: return RNGitPage.ChartColour.push
      case .fetches: return RNGitPage.ChartColour.fetch
      case .views: return RNGitPage.ChartColour.view
      case .downloads: return RNGitPage.ChartColour.download
      }
    }

    /// What the legend calls this category.
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
  }

  /// The line that closes a chart off underneath.
  private static func border(across points: Int) -> String {
    "\u{2514}" + Array(repeating: "\u{2500}", count: points).joined(separator: "") + "\u{2518}\n"
  }

  /// The first and last label, held apart by the width of the chart above them.
  private static func labelLine(_ labels: [String], across points: Int) -> String {
    let width = points + 2
    let first = padded(String(labels[0].prefix(12)), trailing: true)
    let last = padded(String(labels[labels.count - 1].prefix(12)), trailing: false)
    let middle = max(0, width - first.count - last.count)
    return RNGitPage.Colour.dim + first + "`f" + String(repeating: " ", count: middle)
      + RNGitPage.Colour.dim + last + "`f\n"
  }

  /// `text` padded out to twelve characters, on the side the alignment calls for.
  private static func padded(_ text: String, trailing: Bool) -> String {
    let padding = String(repeating: " ", count: max(0, 12 - text.count))
    return trailing ? text + padding : padding + text
  }

  /// `colour` as the six digits it stands for, which a three-digit colour is doubled into.
  static func expanded(_ colour: String) -> String {
    colour.count == 3
      ? colour.map { String(repeating: $0, count: 2) }.joined()
      : String(colour.prefix(6))
  }

  /// The three channels `colour` names.
  static func rgb(of colour: String) -> [Int] {
    stride(from: 0, to: 6, by: 2).map { offset -> Int in
      let start = colour.index(colour.startIndex, offsetBy: offset)
      let end = colour.index(start, offsetBy: 2)
      return Int(colour[start..<end], radix: 16) ?? 0
    }
  }

  /// `colour` taken `fraction` of the way from black towards itself.
  private static func dimmed(_ colour: String, by fraction: Double) -> String {
    rgb(of: colour).map { String(format: "%02x", Int(Double($0) * min(1, fraction))) }.joined()
  }
}
