# SPDX-FileCopyrightText: Copyright (c) 2024-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Performance profiling utilities for NAT workflows."""

import time
import logging
import psutil
import os
import json
import asyncio
from functools import wraps
from typing import Callable, Any, Dict, List
from datetime import datetime
from pydantic import BaseModel, Field
from pathlib import Path


class PerformanceMetrics(BaseModel):
    """Store performance metrics for a function execution."""
    function_name: str
    execution_time_ms: float
    memory_used_mb: float
    memory_peak_mb: float
    timestamp: str
    status: str  # success, error, timeout


class PerformanceProfiler:
    """Profile tool and agent execution performance."""

    def __init__(
        self,
        output_dir: str = "./profiles",
        slow_warning_threshold_ms: float = 5000,
        enabled: bool = True
    ):
        """
        Initialize the performance profiler.

        Args:
            output_dir: Directory to store profiling reports
            slow_warning_threshold_ms: Threshold for slow execution warnings
            enabled: Whether profiling is enabled
        """
        self.output_dir = Path(output_dir)
        self.slow_warning_threshold_ms = slow_warning_threshold_ms
        self.enabled = enabled
        self.metrics: Dict[str, List[Dict]] = {}
        self.logger = logging.getLogger(__name__)

        if self.enabled:
            self.output_dir.mkdir(parents=True, exist_ok=True)
            self.logger.info(f"Performance profiler initialized: {output_dir}")

    def profile_function(
        self,
        track_memory: bool = True,
        slow_warning_ms: Optional[float] = None
    ) -> Callable:
        """
        Decorator to profile a function's performance.

        Args:
            track_memory: Whether to track memory usage
            slow_warning_ms: Custom threshold for slow execution warnings

        Returns:
            Decorated function with profiling
        """

        if slow_warning_ms is None:
            slow_warning_ms = self.slow_warning_threshold_ms

        def decorator(func: Callable) -> Callable:
            @wraps(func)
            async def async_wrapper(*args, **kwargs) -> Any:
                if not self.enabled:
                    return await func(*args, **kwargs)

                process = psutil.Process(os.getpid())

                # Initial memory snapshot
                mem_before = process.memory_info().rss / 1024 / 1024  # MB
                start_time = time.time()
                status = "success"
                result = None

                try:
                    result = await func(*args, **kwargs)
                except Exception as e:
                    self.logger.error(f"Error in {func.__name__}: {str(e)}")
                    status = "error"
                    raise
                finally:
                    # Final measurements
                    end_time = time.time()
                    mem_after = process.memory_info().rss / 1024 / 1024  # MB

                    execution_time_ms = (end_time - start_time) * 1000
                    memory_used_mb = mem_after - mem_before

                    # Log if execution exceeds threshold
                    if execution_time_ms > slow_warning_ms:
                        self.logger.warning(
                            f"Slow execution detected: {func.__name__} took "
                            f"{execution_time_ms:.2f}ms (threshold: {slow_warning_ms}ms)"
                        )

                    # Record metrics
                    metrics = PerformanceMetrics(
                        function_name=func.__name__,
                        execution_time_ms=execution_time_ms,
                        memory_used_mb=memory_used_mb,
                        memory_peak_mb=mem_after,
                        timestamp=datetime.now().isoformat(),
                        status=status
                    )

                    self._record_metrics(metrics)

                    self.logger.info(
                        f"[PROFILE] {func.__name__} | Time: {execution_time_ms:.2f}ms | "
                        f"Memory: {memory_used_mb:.2f}MB | Status: {status}"
                    )

                return result

            @wraps(func)
            def sync_wrapper(*args, **kwargs) -> Any:
                if not self.enabled:
                    return func(*args, **kwargs)

                process = psutil.Process(os.getpid())
                mem_before = process.memory_info().rss / 1024 / 1024
                start_time = time.time()
                status = "success"
                result = None

                try:
                    result = func(*args, **kwargs)
                except Exception as e:
                    self.logger.error(f"Error in {func.__name__}: {str(e)}")
                    status = "error"
                    raise
                finally:
                    end_time = time.time()
                    mem_after = process.memory_info().rss / 1024 / 1024

                    execution_time_ms = (end_time - start_time) * 1000
                    memory_used_mb = mem_after - mem_before

                    if execution_time_ms > slow_warning_ms:
                        self.logger.warning(
                            f"Slow execution: {func.__name__} took "
                            f"{execution_time_ms:.2f}ms"
                        )

                    metrics = PerformanceMetrics(
                        function_name=func.__name__,
                        execution_time_ms=execution_time_ms,
                        memory_used_mb=memory_used_mb,
                        memory_peak_mb=mem_after,
                        timestamp=datetime.now().isoformat(),
                        status=status
                    )

                    self._record_metrics(metrics)
                    self.logger.info(
                        f"[PROFILE] {func.__name__} | Time: {execution_time_ms:.2f}ms | "
                        f"Memory: {memory_used_mb:.2f}MB | Status: {status}"
                    )

                return result

            # Detect if async or sync
            if asyncio.iscoroutinefunction(func):
                return async_wrapper
            else:
                return sync_wrapper

        return decorator

    def _record_metrics(self, metrics: PerformanceMetrics) -> None:
        """Record performance metrics in memory."""
        if metrics.function_name not in self.metrics:
            self.metrics[metrics.function_name] = []

        self.metrics[metrics.function_name].append(metrics.dict())

    def generate_report(self) -> Dict[str, Any]:
        """
        Generate performance report from collected metrics.

        Returns:
            Dictionary containing aggregated performance statistics
        """
        report = {}

        for func_name, metric_list in self.metrics.items():
            if not metric_list:
                continue

            times = [m["execution_time_ms"] for m in metric_list]
            memories = [m["memory_used_mb"] for m in metric_list]
            successful = [m for m in metric_list if m["status"] == "success"]

            report[func_name] = {
                "total_calls": len(metric_list),
                "successful_calls": len(successful),
                "avg_time_ms": sum(times) / len(times),
                "max_time_ms": max(times),
                "min_time_ms": min(times),
                "avg_memory_mb": sum(memories) / len(memories),
                "max_memory_mb": max(memories),
                "success_rate": len(successful) / len(metric_list) if metric_list else 0,
                "slow_executions": sum(1 for t in times if t > self.slow_warning_threshold_ms)
            }

        return report

    def save_report(self, filename: Optional[str] = None) -> str:
        """
        Save performance report to a JSON file.

        Args:
            filename: Optional custom filename

        Returns:
            Path to the saved report file
        """
        if not self.enabled:
            return ""

        report = self.generate_report()

        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"performance_report_{timestamp}.json"

        filepath = self.output_dir / filename

        with open(filepath, 'w') as f:
            json.dump(report, f, indent=2)

        self.logger.info(f"Performance report saved to: {filepath}")
        return str(filepath)

    def print_summary(self) -> None:
        """Print a summary of performance metrics to console."""
        if not self.enabled:
            self.logger.info("Profiling is disabled")
            return

        report = self.generate_report()

        print("\n" + "="*80)
        print("PERFORMANCE PROFILING SUMMARY")
        print("="*80)

        for func_name, stats in report.items():
            print(f"\n{func_name}:")
            print(f"  Total Calls: {stats['total_calls']}")
            print(f"  Success Rate: {stats['success_rate']:.2%}")
            print(f"  Avg Time: {stats['avg_time_ms']:.2f}ms")
            print(f"  Min/Max Time: {stats['min_time_ms']:.2f}ms / {stats['max_time_ms']:.2f}ms")
            print(f"  Avg Memory: {stats['avg_memory_mb']:.2f}MB")
            print(f"  Slow Executions: {stats['slow_executions']}")

        print("\n" + "="*80 + "\n")

    def clear_metrics(self) -> None:
        """Clear all recorded metrics."""
        self.metrics.clear()
        self.logger.info("Performance metrics cleared")
