# SPDX-FileCopyrightText: Copyright (c) 2024-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Guardrails and output validation for NAT workflows to prevent hallucinations."""

import re
import logging
from typing import Any, Dict, List, Optional, Callable
from pydantic import BaseModel, Field
from enum import Enum


class ValidationMode(str, Enum):
    """Validation modes for guardrails."""
    STRICT = "strict"  # Raise exceptions on validation failures
    WARNING = "warning"  # Log warnings but allow execution
    DISABLED = "disabled"  # Disable all validation


class GuardrailRule(BaseModel):
    """A single guardrail rule for validation."""
    name: str
    rule_type: str  # pattern, range, enum, custom
    description: Optional[str] = None
    field: Optional[str] = None
    pattern: Optional[str] = None
    allowed_values: Optional[List[str]] = None
    min_value: Optional[float] = None
    max_value: Optional[float] = None


class OutputValidator:
    """Validate agent outputs and enforce guardrails to prevent hallucinations."""

    def __init__(
        self,
        mode: ValidationMode = ValidationMode.STRICT,
        rules: Optional[List[GuardrailRule]] = None
    ):
        self.mode = mode
        self.rules = rules or []
        self.logger = logging.getLogger(__name__)

    def add_rule(self, rule: GuardrailRule) -> None:
        """Add a guardrail rule to the validator."""
        self.rules.append(rule)
        self.logger.info(f"Added guardrail rule: {rule.name}")

    def validate_output(self, output: Any, context: Optional[Dict[str, Any]] = None) -> bool:
        """
        Validate output against all configured rules.

        Args:
            output: The output to validate
            context: Optional context for validation

        Returns:
            True if validation passes, False otherwise

        Raises:
            ValueError: If validation fails in STRICT mode
        """

        if self.mode == ValidationMode.DISABLED:
            return True

        context = context or {}
        violations = []

        for rule in self.rules:
            try:
                if not self._apply_rule(output, rule, context):
                    violations.append(f"Rule '{rule.name}' violated")
            except Exception as e:
                self.logger.error(f"Error applying rule {rule.name}: {str(e)}")
                if self.mode == ValidationMode.STRICT:
                    raise

        if violations:
            message = "Output validation failed: " + "; ".join(violations)
            if self.mode == ValidationMode.STRICT:
                raise ValueError(message)
            else:
                self.logger.warning(message)
                return False

        return True

    def _apply_rule(self, output: Any, rule: GuardrailRule, context: Dict) -> bool:
        """Apply a single validation rule to output."""

        if rule.rule_type == "pattern":
            if isinstance(output, str):
                pattern = re.compile(rule.pattern)
                return bool(pattern.match(output))
            return False

        elif rule.rule_type == "enum":
            if rule.field:
                field_value = output.get(rule.field) if isinstance(output, dict) else getattr(output, rule.field, None)
                return field_value in rule.allowed_values
            return output in rule.allowed_values

        elif rule.rule_type == "range":
            if rule.field:
                field_value = output.get(rule.field) if isinstance(output, dict) else getattr(output, rule.field, None)
            else:
                field_value = output

            if rule.min_value is not None and field_value < rule.min_value:
                return False
            if rule.max_value is not None and field_value > rule.max_value:
                return False
            return True

        return True

    def validate_llm_response(self, response: str, tool_name: str) -> Dict[str, Any]:
        """
        Validate LLM response before tool execution to detect hallucinations.

        Args:
            response: The LLM response text
            tool_name: The expected tool name

        Returns:
            Dictionary with validation results including is_valid, issues, and confidence
        """

        validations = {
            "is_valid": True,
            "tool_name": tool_name,
            "issues": [],
            "confidence": 1.0
        }

        # Check for hallucinated tool calls
        if self._contains_hallucinated_calls(response):
            validations["issues"].append("Detected potentially hallucinated tool calls")
            validations["is_valid"] = False
            validations["confidence"] = 0.5

        # Check for contradictory statements
        if self._contains_contradictions(response):
            validations["issues"].append("Response contains contradictory statements")
            validations["is_valid"] = False
            validations["confidence"] = 0.7

        # Semantic validation
        if not self._validate_semantics(response, tool_name):
            validations["issues"].append("Response fails semantic validation")
            validations["is_valid"] = False
            validations["confidence"] = 0.6

        if not validations["is_valid"]:
            self.logger.warning(
                f"LLM response validation failed for {tool_name}: {validations['issues']}"
            )

        return validations

    def _contains_hallucinated_calls(self, response: str) -> bool:
        """Detect hallucinated tool calls that don't exist."""
        # Look for invalid tool names
        invalid_tools = ["invalid_tool", "unknown_tool", "fake_function"]
        response_lower = response.lower()

        return any(invalid in response_lower for invalid in invalid_tools)

    def _contains_contradictions(self, response: str) -> bool:
        """Detect contradictory statements in response."""
        contradictions = [
            (r"packet.*loss.*detected", r"no.*issue|no.*problem|all.*good"),
            (r"error.*occurred", r"successfully.*completed"),
            (r"failed", r"success"),
        ]

        response_lower = response.lower()

        for pattern1, pattern2 in contradictions:
            if re.search(pattern1, response_lower) and re.search(pattern2, response_lower):
                return True

        return False

    def _validate_semantics(self, response: str, tool_name: str) -> bool:
        """Validate semantic appropriateness of response for the tool."""

        if tool_name == "reconfigure_network":
            required_keywords = ["bandwidth", "allocation", "configuration", "reconfigure", "slice"]
            has_keywords = any(kw in response.lower() for kw in required_keywords)
            return has_keywords

        elif tool_name == "get_packetloss_logs":
            required_keywords = ["packet", "loss", "data", "logs", "metrics"]
            has_keywords = any(kw in response.lower() for kw in required_keywords)
            return has_keywords

        return True


class InputValidator:
    """Validate tool inputs before execution to prevent invalid operations."""

    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def validate_reconfigure_input(
        self,
        ue: str,
        value_1_old: int,
        value_2_old: int
    ) -> tuple[bool, List[str]]:
        """
        Validate reconfigure_network input parameters.

        Args:
            ue: User Equipment identifier
            value_1_old: Old bandwidth value for slice 1
            value_2_old: Old bandwidth value for slice 2

        Returns:
            Tuple of (is_valid, list of issues)
        """

        issues = []

        # Validate UE identifier
        if ue.upper() not in ["UE1", "UE2"]:
            issues.append(f"Invalid UE: {ue}. Must be 'UE1' or 'UE2'")

        # Validate bandwidth values are in range
        if not (0 <= value_1_old <= 100):
            issues.append(f"value_1_old {value_1_old} out of range [0-100]")

        if not (0 <= value_2_old <= 100):
            issues.append(f"value_2_old {value_2_old} out of range [0-100]")

        # Ensure values sum to 100 (total bandwidth)
        if value_1_old + value_2_old != 100:
            issues.append(f"Bandwidth values must sum to 100, got {value_1_old + value_2_old}")

        is_valid = len(issues) == 0

        if not is_valid:
            self.logger.warning(f"Input validation failed: {'; '.join(issues)}")

        return is_valid, issues

    def validate_packetloss_input(self, limit: int) -> tuple[bool, List[str]]:
        """
        Validate get_packetloss_logs input parameters.

        Args:
            limit: Maximum number of log entries to retrieve

        Returns:
            Tuple of (is_valid, list of issues)
        """

        issues = []

        if limit <= 0:
            issues.append(f"Limit must be positive, got {limit}")

        if limit > 10000:
            issues.append(f"Limit too large: {limit}. Maximum is 10000")

        is_valid = len(issues) == 0

        if not is_valid:
            self.logger.warning(f"Input validation failed: {'; '.join(issues)}")

        return is_valid, issues
