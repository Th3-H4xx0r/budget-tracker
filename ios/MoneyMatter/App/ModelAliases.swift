import MoneyMatterKit

// `Transaction` also exists in SwiftUI, and `Category` in the Objective-C runtime. Declaring
// these aliases in the app module makes the MoneyMatterKit models win inside the app.
// Write `SwiftUI.Transaction` for the animation type.
typealias Transaction = MoneyMatterKit.Transaction
typealias Category = MoneyMatterKit.Category
