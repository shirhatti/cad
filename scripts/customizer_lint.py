#!/usr/bin/env python3
"""
MakerBot Customizer Linter for OpenSCAD files.

Validates that OpenSCAD files comply with the MakerBot Customizer specification:
https://customizer.makerbot.com/docs

Usage:
    python customizer_lint.py file1.scad file2.scad ...
    python customizer_lint.py --check-all projects/
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


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


# Regex patterns for parsing OpenSCAD
PATTERNS = {
    # Module or function declaration
    "module_decl": re.compile(r"^\s*module\s+\w+\s*\("),
    "function_decl": re.compile(r"^\s*function\s+\w+\s*\("),

    # Tab declaration: /* [Tab Name] */
    "tab_decl": re.compile(r"^\s*/\*\s*\[([^\]]+)\]\s*\*/\s*$"),

    # Variable assignment: var_name = value;
    "var_assignment": re.compile(
        r"^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+?)\s*;\s*(?://\s*(.*))?$"
    ),

    # Description comment: // description text
    "description_comment": re.compile(r"^\s*//\s*(.+)$"),

    # Block comment start
    "block_comment_start": re.compile(r"^\s*/\*"),

    # Block comment end
    "block_comment_end": re.compile(r"\*/\s*$"),

    # Preview directive: // preview[view:X, tilt:Y]
    "preview_directive": re.compile(r"^\s*//\s*preview\["),

    # Slider annotation: [min:max] or [min:step:max] or [max]
    "slider_annotation": re.compile(r"^\[(\d+(?:\.\d+)?(?::\d+(?:\.\d+)?){0,2})\]$"),

    # Dropdown annotation: [val1, val2, ...] or [val1:Label1, val2:Label2, ...]
    "dropdown_annotation": re.compile(r"^\[([^\[\]]+(?:,[^\[\]]+)*)\]$"),

    # Image surface annotation: [image_surface:WxH]
    "image_surface": re.compile(r"^\[image_surface:\d+x\d+\]$"),

    # Image array annotation: [image_array:WxH]
    "image_array": re.compile(r"^\[image_array:\d+x\d+\]$"),

    # Polygon canvas annotation: [draw_polygon:WxH]
    "draw_polygon": re.compile(r"^\[draw_polygon:\d+x\d+\]$"),

    # Special variable assignments ($fn, $fa, $fs)
    "special_var": re.compile(r"^\s*\$[a-z]+\s*="),

    # Computed value (contains operators or references other variables)
    "computed_value": re.compile(r"[+\-*/]|[a-zA-Z_][a-zA-Z0-9_]*\s*[+\-*/]"),
}

# Reserved tab names
RESERVED_TABS = {"Global", "Hidden"}

# Valid preview view options
VALID_VIEWS = {
    "north", "north east", "east", "south east",
    "south", "south west", "west", "north west"
}

# Valid preview tilt options
VALID_TILTS = {
    "top", "top diagonal", "side", "bottom diagonal", "bottom"
}


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
    if PATTERNS["slider_annotation"].match(annotation):
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
    if PATTERNS["dropdown_annotation"].match(annotation):
        return ("dropdown", True)

    # If it starts with [ but doesn't match known patterns
    if annotation.startswith("["):
        return ("unknown", False)

    return ("none", True)


def is_valid_default_value(value: str) -> tuple[bool, str]:
    """
    Check if a default value is valid for Customizer.

    Valid values: numbers, quoted strings, booleans, arrays of numbers/strings.
    Invalid: expressions with operators, variable references.

    Returns:
        Tuple of (is_valid, reason if invalid)
    """
    value = value.strip()

    # Number (int or float)
    if re.match(r"^-?\d+(?:\.\d+)?$", value):
        return (True, "")

    # Quoted string
    if re.match(r'^"[^"]*"$', value):
        return (True, "")

    # Boolean
    if value in ("true", "false"):
        return (True, "")

    # Array literal (simplified check)
    if value.startswith("[") and value.endswith("]"):
        # Check if it contains operators outside of the array
        inner = value[1:-1]
        # Simple array of numbers/strings is OK
        if re.match(r"^[\d.,\s\-\"\'a-zA-Z_:]+$", inner):
            return (True, "")
        # Check for computed values
        if PATTERNS["computed_value"].search(inner):
            return (False, "contains computed expression")
        return (True, "")

    # Variable reference or computed value
    if PATTERNS["computed_value"].search(value):
        return (False, "contains computed expression (won't appear in Customizer UI)")

    # References another variable
    if re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", value):
        return (False, "references another variable (won't appear in Customizer UI)")

    return (True, "")


def lint_file(filepath: Path) -> LintResult:
    """Lint a single OpenSCAD file for Customizer compliance."""
    result = LintResult(file=filepath)

    try:
        content = filepath.read_text()
    except Exception as e:
        result.errors.append(LintError(
            file=filepath,
            line=0,
            message=f"Could not read file: {e}"
        ))
        return result

    lines = content.split("\n")

    # State tracking
    in_parameter_section = True  # Before first module/function
    current_tab: str | None = None
    in_block_comment = False
    previous_description: str | None = None
    found_any_tab = False
    found_any_param = False
    param_without_tab_warning_issued = False
    line_num = 0

    for i, line in enumerate(lines, start=1):
        line_num = i
        stripped = line.strip()

        # Skip empty lines
        if not stripped:
            previous_description = None
            continue

        # Track block comments
        if PATTERNS["block_comment_start"].search(stripped):
            # Check if it's a tab declaration
            tab_match = PATTERNS["tab_decl"].match(stripped)
            if tab_match:
                current_tab = tab_match.group(1)
                found_any_tab = True
                previous_description = None
                continue
            in_block_comment = True
            continue

        if in_block_comment:
            if PATTERNS["block_comment_end"].search(stripped):
                in_block_comment = False
            continue

        # Check for module/function declaration (end of parameter section)
        if PATTERNS["module_decl"].search(stripped) or PATTERNS["function_decl"].search(stripped):
            in_parameter_section = False
            previous_description = None
            continue

        # Check for description comments
        if PATTERNS["description_comment"].match(stripped):
            # Skip preview directives
            if PATTERNS["preview_directive"].match(stripped):
                previous_description = None
                continue
            desc_match = PATTERNS["description_comment"].match(stripped)
            if desc_match:
                previous_description = desc_match.group(1)
            continue

        # Check for special variables ($fn, $fa, $fs)
        if PATTERNS["special_var"].match(stripped):
            previous_description = None
            continue

        # Check for variable assignments
        var_match = PATTERNS["var_assignment"].match(stripped)
        if var_match:
            var_name = var_match.group(1)
            var_value = var_match.group(2)
            annotation = var_match.group(3) or ""

            # Skip if in Hidden tab
            if current_tab == "Hidden":
                previous_description = None
                continue

            found_any_param = True

            # Check if parameter is in the parameter section
            if not in_parameter_section:
                result.warnings.append(LintError(
                    file=filepath,
                    line=i,
                    message=f"Parameter '{var_name}' is after module declarations (won't be customizable)",
                    severity="warning"
                ))

            # Check if parameter has a tab
            if not found_any_tab and not param_without_tab_warning_issued:
                result.warnings.append(LintError(
                    file=filepath,
                    line=i,
                    message="Parameters should be organized into tabs using /* [Tab Name] */",
                    severity="warning"
                ))
                param_without_tab_warning_issued = True

            # Check for description
            if not previous_description and current_tab != "Hidden":
                result.warnings.append(LintError(
                    file=filepath,
                    line=i,
                    message=f"Parameter '{var_name}' lacks a description comment",
                    severity="warning"
                ))

            # Check default value validity
            is_valid_val, reason = is_valid_default_value(var_value)
            if not is_valid_val:
                result.warnings.append(LintError(
                    file=filepath,
                    line=i,
                    message=f"Parameter '{var_name}' {reason}",
                    severity="warning"
                ))

            # Check annotation validity
            if annotation:
                ann_type, ann_valid = parse_annotation(annotation)
                if not ann_valid:
                    result.errors.append(LintError(
                        file=filepath,
                        line=i,
                        message=f"Parameter '{var_name}' has invalid annotation: {annotation}"
                    ))
            else:
                # No annotation - that's OK but worth noting for sliders/dropdowns
                if is_valid_val and current_tab != "Hidden":
                    result.warnings.append(LintError(
                        file=filepath,
                        line=i,
                        message=f"Parameter '{var_name}' has no UI annotation (will be a text input)",
                        severity="warning"
                    ))

            previous_description = None
            continue

        previous_description = None

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
