import phoenix as px
from openinference.instrumentation.langchain import LangChainInstrumentor
from opentelemetry import trace as trace_api
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk import trace as trace_sdk
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

def setup_phoenix_tracing(endpoint: str = "http://0.0.0.0:6006"):
    """Setup Phoenix tracing for LangChain/NAT workflows."""

    # Launch Phoenix in the background
    session = px.launch_app()

    # Setup tracer using Phoenix's built-in method (avoids 405 errors)
    tracer_provider = trace_sdk.TracerProvider()
    trace_api.set_tracer_provider(tracer_provider)

    # Use Phoenix's collector endpoint (not OTLP endpoint to avoid 405)
    # Phoenix expects data on its own collector, not standard OTLP v1/traces
    otlp_exporter = OTLPSpanExporter(endpoint=f"{endpoint}")
    tracer_provider.add_span_processor(SimpleSpanProcessor(otlp_exporter))

    # Instrument LangChain with skip_dep_check to avoid message type errors
    LangChainInstrumentor().instrument(
        tracer_provider=tracer_provider,
        skip_dep_check=True  # Skip dependency checks that cause type errors
    )

    print(f"Phoenix tracing enabled: {endpoint}")
