/// Protocol for rendering a Micron AST.
///
/// Conforming types translate `[MicronNode]` into a platform-specific output
/// (SwiftUI views, attributed strings, plain text, HTML, etc.).
///
/// This protocol defines only the interface; concrete renderers are provided
/// by downstream targets (e.g. RetiOS).
public protocol MicronRenderer {
    /// The output type produced by this renderer.
    associatedtype Output

    /// Render a complete parsed document.
    ///
    /// - Parameter nodes: The AST produced by `MicronParser.parse(_:)`.
    /// - Returns: Platform-specific rendered output.
    func render(_ nodes: [MicronNode]) -> Output

    /// Render a single AST node.
    ///
    /// - Parameter node: One `MicronNode`.
    /// - Returns: Platform-specific rendered output for that node.
    func render(node: MicronNode) -> Output

    /// Render a single inline span.
    ///
    /// - Parameter span: One `MicronSpan`.
    /// - Returns: Platform-specific rendered output for that span.
    func render(span: MicronSpan) -> Output
}
