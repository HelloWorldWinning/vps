

async def unknown(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text( "The type of your input is not supported" )



async def refresh_chat_page(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    global api  
    api.refresh_chat_page() 
    login_chatgpt()
    await update.message.reply_text(f' refresh_chat_page and  conversation_id is : { CONVERSATION_ID} ')
    
app.add_handler(CommandHandler("rc",  refresh_chat_page))

    
app.add_handler(MessageHandler(filters.TEXT, send_to_tgbot))
app.add_handler(MessageHandler(filters.VIDEO, unknown))
app.add_handler(MessageHandler(filters.PHOTO, unknown))
app.run_polling()    


