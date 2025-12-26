#!/usr/bin/env python3
"""
MakerBot Customizer Linter for OpenSCAD files.

Validates that OpenSCAD files comply with the MakerBot Customizer specification:
https://customizer.makerbot.com/docs

Usage:
    uv run python -m scripts.customizer_lint file1.scad file2.scad ...
    uv run python -m scripts.customizer_lint projects/
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import tree_sitter as ts
import tree_sitter_openscad as ts_openscad


@dataclass
class LintError:
    """A linting error with location and message."""
    file: Path
    line: int
    message: str
    severity: str = "error"  # "error" or "warning"

    def __str__(self) -> str:
        return f"{self.file}:{self.line}: {self.severity}: {self.message}"


@dataclass
class LintResult:
    """Result of linting a file."""
    file: Path
    errors: list[LintError] = field(default_factory=list)
    warnings: list[LintError] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return len(self.errors) == 0


# Regex patterns for annotation validation
PATTERNS = {
    # Tab declaration: /* [Tab Name] */
    "tab_decl": re.compile(r"^\s*/\*\s*\[([^\]]+)\]\s*\*/\s*$"),

    # Slider annotation: [min:max] or [min:step:max] or [max]
    "slider": re.compile(r"^\[(-?\d+(?:\.\d+)?(?::-?\d+(?:\.\d+)?){0,2})\]$"),

    # Dropdown annotation: [val1, val2, ...] or [val1:Label1, val2:Label2, ...]
    "dropdown": re.compile(r"^\[([^\[\]]+(?:,[^\[\]]+)*)\]$"),

    # Image surface annotation: [image_surface:WxH]
    "image_surface": re.compile(r"^\[image_surface:\d+x\d+\]$"),

    # Image array annotation: [image_array:WxH]
    "image_array": re.compile(r"^\[image_array:\d+x\d+\]$"),

    # Polygon canvas annotation: [draw_polygon:WxH]
    "draw_polygon": re.compile(r"^\[draw_polygon:\d+x\d+\]$"),

    # Preview directive
    "preview": re.compile(r"^\s*//\s*preview\["),

    # Annotation in comment: // [...]
    "annotation_comment": re.compile(r"//\s*(\[[^\]]+\])\s*$"),
}

# Reserved tab names
RESERVED_TABS = {"Global", "Hidden"}

# Create parser once
_parser = ts.Parser(ts.Language(ts_openscad.language()))


def parse_annotation(annotation: str) -> tuple[str, bool]:
    """
    Parse a parameter annotation and return its type and validity.

    Returns:
        Tuple of (annotation_type, is_valid)
    """
    annotation = annotation.strip()

    if not annotation:
        return ("none", True)

    # Check for slider annotation
    if PATTERNS["slider"].match(annotation):
        return ("slider", True)

    # Check for image surface
    if PATTERNS["image_surface"].match(annotation):
        return ("image_surface", True)

    # Check for image array
    if PATTERNS["image_array"].match(annotation):
        return ("image_array", True)

    # Check for polygon canvas
    if PATTERNS["draw_polygon"].match(annotation):
        return ("draw_polygon", True)

    # Check for dropdown annotation
    if PATTERNS["dropdown"].match(annotation):
        return ("dropdown", True)

    # If it starts with [ but doesn't match known patterns
    if annotation.startswith("["):
        return ("unknown", False)

    return ("none", True)


def get_value_type(node: ts.Node) -> tuple[str, bool, str]:
    """
    Analyze a value node to determine if it's valid for Customizer.

    Returns:
        Tuple of (value_type, is_computed, reason)
    """
    node_type = node.type

    if node_type == "integer" or node_type == "float":
        return ("number", False, "")

    if node_type == "string":
        return ("string", False, "")

    if node_type == "boolean":
        return ("boolean", False, "")

    if node_type == "list":
        # Check if any child is an identifier or expression
        for child in node.children:
            if child.type == "identifier":
                return ("list", True, "list contains variable reference")
            if child.type == "binary_expression":
                return ("list", True, "list contains computed expression")
        return ("list", False, "")

    if node_type == "binary_expression":
        return ("expression", True, "computed expression won't appear in Customizer UI")

    if node_type == "unary_expression":
        # Negative numbers are OK
        child = node.children[-1] if node.children else None
        if child and child.type in ("integer", "float"):
            return ("number", False, "")
        return ("expression", True, "computed expression won't appear in Customizer UI")

    if node_type == "identifier":
        return ("reference", True, "variable reference won't appear in Customizer UI")

    if node_type == "ternary_expression":
        return ("expression", True, "ternary expression won't appear in Customizer UI")

    if node_type == "function_call":
        return ("expression", True, "function call won't appear in Customizer UI")

    return ("unknown", False, "")


def lint_file(filepath: Path) -> LintResult:
    """Lint a single OpenSCAD file for Customizer compliance."""
    result = LintResult(file=filepath)

    try:
        content = filepath.read_bytes()
    except Exception as e:
        result.errors.append(LintError(
            file=filepath,
            line=0,
            message=f"Could not read file: {e}"
        ))
        return result

    tree = _parser.parse(content)
    root = tree.root_node

    # State tracking
    current_tab: str | None = None
    in_parameter_section = True
    found_any_tab = False
    found_any_param = False
    param_without_tab_warning_issued = False
    previous_comment: ts.Node | None = None
    previous_was_description = False

    # Walk through top-level nodes
    for node in root.children:
        line = node.start_point.row + 1  # 1-indexed

        # Check for module/function declaration (end of parameter section)
        if node.type in ("module_item", "function_item"):
            in_parameter_section = False
            previous_comment = None
            previous_was_description = False
            continue

        # Check for block comments (tab declarations)
        if node.type == "block_comment":
            text = node.text.decode() if node.text else ""
            tab_match = PATTERNS["tab_decl"].match(text)
            if tab_match:
                current_tab = tab_match.group(1)
                found_any_tab = True
            previous_comment = None
            previous_was_description = False
            continue

        # Check for line comments
        if node.type == "line_comment":
            text = node.text.decode() if node.text else ""

            # Skip preview directives
            if PATTERNS["preview"].match(text):
                previous_comment = None
                previous_was_description = False
                continue

            # Check if it's an annotation comment (follows a variable)
            if PATTERNS["annotation_comment"].search(text):
                # This is an annotation, not a description
                previous_comment = None
                previous_was_description = False
            else:
                # This is a description for the next variable
                previous_comment = node
                previous_was_description = True
            continue

        # Check for variable declarations
        if node.type == "var_declaration":
            # Find the assignment node
            assignment = None
            for child in node.children:
                if child.type == "assignment":
                    assignment = child
                    break

            if not assignment:
                previous_comment = None
                previous_was_description = False
                continue

            # Get variable name and value
            var_name = None
            var_value = None
            for child in assignment.children:
                if child.type == "identifier" and var_name is None:
                    var_name = child.text.decode() if child.text else ""
                elif child.type not in ("=", "identifier"):
                    var_value = child

            if not var_name or var_name.startswith("$"):
                # Skip special variables like $fn
                previous_comment = None
                previous_was_description = False
                continue

            # Skip if in Hidden tab
            if current_tab == "Hidden":
                previous_comment = None
                previous_was_description = False
                continue

            found_any_param = True

            # Check if parameter is after module declarations
            if not in_parameter_section:
                result.warnings.append(LintError(
                    file=filepath,
                    line=line,
                    message=f"Parameter '{var_name}' is after module declarations (won't be customizable)",
                    severity="warning"
                ))

            # Check if parameter has a tab
            if not found_any_tab and not param_without_tab_warning_issued:
                result.warnings.append(LintError(
                    file=filepath,
                    line=line,
                    message="Parameters should be organized into tabs using /* [Tab Name] */",
                    severity="warning"
                ))
                param_without_tab_warning_issued = True

            # Check for description (previous comment should be a description)
            if not previous_was_description:
                result.warnings.append(LintError(
                    file=filepath,
                    line=line,
                    message=f"Parameter '{var_name}' lacks a description comment",
                    severity="warning"
                ))

            # Check value type
            if var_value:
                value_type, is_computed, reason = get_value_type(var_value)
                if is_computed:
                    result.warnings.append(LintError(
                        file=filepath,
                        line=line,
                        message=f"Parameter '{var_name}': {reason}",
                        severity="warning"
                    ))

            # Look for annotation in the next sibling (line comment after var)
            # Find the node index and check the next sibling
            annotation_found = False
            node_idx = root.children.index(node)
            if node_idx + 1 < len(root.children):
                next_node = root.children[node_idx + 1]
                if next_node.type == "line_comment":
                    comment_text = next_node.text.decode() if next_node.text else ""
                    ann_match = PATTERNS["annotation_comment"].search(comment_text)
                    if ann_match:
                        annotation = ann_match.group(1)
                        ann_type, ann_valid = parse_annotation(annotation)
                        if not ann_valid:
                            result.errors.append(LintError(
                                file=filepath,
                                line=next_node.start_point.row + 1,
                                message=f"Parameter '{var_name}' has invalid annotation: {annotation}"
                            ))
                        annotation_found = True

            if not annotation_found and not is_computed:
                result.warnings.append(LintError(
                    file=filepath,
                    line=line,
                    message=f"Parameter '{var_name}' has no UI annotation (will be a text input)",
                    severity="warning"
                ))

            previous_comment = None
            previous_was_description = False
            continue

        previous_comment = None
        previous_was_description = False

    # Check if any parameters were found
    if not found_any_param:
        result.errors.append(LintError(
            file=filepath,
            line=1,
            message="No Customizer parameters found - file is not customizable"
        ))

    return result


def lint_directory(dirpath: Path, recursive: bool = True) -> list[LintResult]:
    """Lint all OpenSCAD files in a directory."""
    results = []

    pattern = "**/*.scad" if recursive else "*.scad"
    for scad_file in sorted(dirpath.glob(pattern)):
        results.append(lint_file(scad_file))

    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint OpenSCAD files for MakerBot Customizer compliance"
    )
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="Files or directories to lint"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors"
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only show errors, not warnings"
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output"
    )

    args = parser.parse_args()

    # ANSI color codes
    if args.no_color or not sys.stdout.isatty():
        RED, YELLOW, GREEN, RESET = "", "", "", ""
    else:
        RED, YELLOW, GREEN, RESET = "\033[91m", "\033[93m", "\033[92m", "\033[0m"

    all_results: list[LintResult] = []

    for path in args.paths:
        if path.is_file():
            all_results.append(lint_file(path))
        elif path.is_dir():
            all_results.extend(lint_directory(path))
        else:
            print(f"{RED}Error: {path} is not a file or directory{RESET}", file=sys.stderr)
            return 1

    # Print results
    total_errors = 0
    total_warnings = 0

    for result in all_results:
        for error in result.errors:
            print(f"{RED}{error}{RESET}")
            total_errors += 1

        if not args.quiet:
            for error in result.warnings:
                print(f"{YELLOW}{error}{RESET}")
                total_warnings += 1

    # Summary
    if all_results:
        passed = sum(1 for r in all_results if r.passed)
        failed = len(all_results) - passed

        if args.strict:
            failed = sum(1 for r in all_results if r.errors or r.warnings)
            passed = len(all_results) - failed

        print()
        if failed == 0:
            print(f"{GREEN}All {len(all_results)} file(s) passed Customizer linting{RESET}")
        else:
            print(f"{RED}{failed} file(s) failed, {passed} passed{RESET}")
            print(f"  {total_errors} error(s), {total_warnings} warning(s)")

    if args.strict:
        return 1 if (total_errors + total_warnings) > 0 else 0
    return 1 if total_errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
