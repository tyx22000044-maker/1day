import Foundation

extension Double {
    var cleanAmountText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.2f", self)
    }

    var currencyAmountText: String {
        String(format: "%.2f", self)
    }
}
