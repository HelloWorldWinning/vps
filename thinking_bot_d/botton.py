DEFAULT_BUTTON_LIST = [
    "天地不仁 以万物为刍狗",
    "胜兵先胜而后求战，败兵先战而后求胜"
]


def initialize_button_texts():
    try:
        response = requests.get('https://raw.githubusercontent.com/HelloWorldWinning/vps/main/thinking_bot_d/button_list.txt')
        if response.status_code == 200:
            fetched_list = [line.strip() for line in response.text.split('\n') if line.strip()]
            return fetched_list if fetched_list else DEFAULT_BUTTON_LIST
        return DEFAULT_BUTTON_LIST
    except Exception as e:
        print(f"Error fetching button texts at startup: {e}")
        return DEFAULT_BUTTON_LIST


print(initialize_button_texts())
