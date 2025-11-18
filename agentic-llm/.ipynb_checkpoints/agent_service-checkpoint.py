import os
import sys
from dotenv import load_dotenv
import gradio as gr

try:
    from langgraph_agent import get_agent_executor
    from chatbot_DLI import build_gradio_ui
except ImportError as e:
    print(f"Error: Failed to import modules. {e}")
    print("This script assumes 'langgraph_agent.py' has 'get_agent_executor()'")
    print("and 'chatbot_DLI.py' has 'build_gradio_ui()'.")
    sys.exit(1)


def main():

    load_dotenv()
    print("--- Agent Service Started ---")

    if not os.getenv("NVIDIA_API_KEY"):
        print("Warning: NVIDIA_API_KEY is not set. The agent may fail.")

    try:
        print("Initializing agent executor...")
        agent_executor = get_agent_executor()
        print("Agent executor initialized.")

        print("Building Gradio UI...")
        app = build_gradio_ui(agent_executor)
        print("Gradio UI built.")

        print("Launching Gradio UI on http://0.0.0.0:7860")
        app.launch(server_name="0.0.0.0", server_port=7860)

    except AttributeError as e:
        print(f"--- FATAL ERROR: Missing Function ---")
        print(f"Error: {e}")
        print(
            "This script assumes 'langgraph_agent.py' has a 'get_agent_executor()' function"
        )
        print("and 'chatbot_DLI.py' has a 'build_gradio_ui(agent_executor)' function.")
        print(
            "Please check those files and update the names in this script if they are different."
        )
        sys.exit(1)
    except Exception as e:
        print(f"--- FATAL ERROR in Agent Service: {e} ---")
        sys.exit(1)
    except KeyboardInterrupt:
        print("--- Agent Service Shutting Down ---")
        sys.exit(0)


if __name__ == "__main__":
    main()
