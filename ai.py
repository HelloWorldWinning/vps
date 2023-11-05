import openai
import os
import interpreter as chatgpt
import interpreter

chatgpt.model = "gpt-3.5-turbo"
chatgpt.auto_run = True


api_key_main   = os.getenv("OPENAI_API_KEY")

api_key_backup = os.getenv("OPENAI_API_KEY_BACKUP")


def c(string):
    try:
        #         return chatgpt.chat(str(string))
        chatgpt.chat(str(string))
    except openai.error.RateLimitError as e:
        #         print("Rate limit error caught:", e)
        # print("Limit: 3 / min")
        chatgpt.api_key = api_key_backup
        chatgpt.chat(str(string))
        chatgpt.api_key = api_key_main
    except Exception as e:
        print(e)


def cc():
    try:
        chatgpt.reset()
    except Exception as e:
        print(e)
