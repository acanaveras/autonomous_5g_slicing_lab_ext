import phoenix as px
from openinference.instrumentation.langchain import LangChainInstrumentor
from opentelemetry import trace as trace_api
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk import trace as trace_sdk
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

def setup_phoenix_tracing(endpoint: str = "http://0.0.0.0:6006"):
    """Setup Phoenix tracing for LangChain/NAT workflows."""
    
    # Launch Phoenix in the background
    px.launch_app()
    
    # Setup tracer
    tracer_provider = trace_sdk.TracerProvider()
    trace_api.set_tracer_provider(tracer_provider)
    
    # Setup OTLP exporter to Phoenix
    otlp_exporter = OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces")
    tracer_provider.add_span_processor(SimpleSpanProcessor(otlp_exporter))
    
    # Instrument LangChain
    LangChainInstrumentor().instrument(tracer_provider=tracer_provider)
    
    print(f"Phoenix tracing enabled: {endpoint}")
