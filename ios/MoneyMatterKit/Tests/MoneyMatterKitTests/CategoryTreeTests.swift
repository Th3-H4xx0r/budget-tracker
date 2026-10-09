import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("CategoryTree")
struct CategoryTreeTests {
    @Test("Builds nested children and moves internal roots last")
    func buildsTree() throws {
        let categories = try Fixture.decode(Endpoints.categories(), from: "categories")
        let tree = CategoryTree.build(from: categories)

        #expect(tree.map(\.id) == ["c-food", "c-orphan", "c-other"])
        let food = try #require(tree.first)
        #expect(food.children.map(\.id) == ["c-restaurants"])
        #expect(food.children.first?.children.map(\.id) == ["c-cafe"])
    }

    @Test("A category whose parent is missing becomes a root")
    func orphanBecomesRoot() {
        let tree = CategoryTree.build(from: [Category(id: "x", name: "X", parentId: "missing")])
        #expect(tree.map(\.id) == ["x"])
    }

    @Test("A parent cycle doesn't loop forever and keeps every category")
    func cycle() {
        let categories = [
            Category(id: "a", name: "A", parentId: "b"),
            Category(id: "b", name: "B", parentId: "a"),
            Category(id: "self", name: "Self", parentId: "self"),
        ]
        let tree = CategoryTree.build(from: categories)
        let flattened = CategoryTree.flatten(tree)
        #expect(Set(flattened.map(\.id)) == ["a", "b", "self"])
        #expect(flattened.count == 3)
    }

    @Test("Flatten lists depth-first with depths")
    func flatten() throws {
        let categories = try Fixture.decode(Endpoints.categories(), from: "categories")
        let flattened = CategoryTree.flatten(CategoryTree.build(from: categories))
        #expect(flattened.map(\.id) == ["c-food", "c-restaurants", "c-cafe", "c-orphan", "c-other"])
        #expect(flattened.map(\.depth) == [0, 1, 2, 0, 0])
    }

    @Test("Path walks from the root down to the category")
    func path() throws {
        let categories = try Fixture.decode(Endpoints.categories(), from: "categories")
        #expect(CategoryTree.path(to: "c-cafe", in: categories).map(\.name) == ["Food & Drinks", "Restaurants", "Cafe"])
        #expect(CategoryTree.path(to: "nope", in: categories).isEmpty)
    }

    @Test("An empty list builds an empty tree")
    func empty() {
        #expect(CategoryTree.build(from: []).isEmpty)
    }
}
