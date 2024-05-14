                full_html = f'''
    <!DOCTYPE html>
    <html>
    <head>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-mml-chtml.min.js" async></script>
        <title>{file_title}</title>

        <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:ital,wght@0,100..700;1,100..700&display=swap" rel="stylesheet">
        <link href="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap" rel="stylesheet">
        <link rel="icon" href="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_files/my_logo/favicon.ico" type="image/x-icon">
        <style>
            @font-face {{
                font-family: 'FZFangJunHeiS';
                src: url('https://github.com/HelloWorldWinning/vps/raw/main/folder_font_test/FZFangJunHeiS/FZFangJunHeiS_Regular.ttf') format('truetype');
            }}
            body {{
                  font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
            padding: 20px;
            line-height: 1.6;
            text-align: justify;
            text-justify: inter-word;
                  }}
            pre {{
            background-color: #ffffff;
                font-family: 'Source Code Pro', 'FZFangJunHeiS', monospace;
                white-space: pre-wrap;
                word-wrap: break-word;

                text-align: justify;
                text-justify: inter-word;
            }}

            img, pre, table {{ max-width: 100%; overflow-x: auto; }}

            /* TOC styles */
            .toc {{
                background-color: #f9f9f9;
                border: 1px solid #ccc;
                padding: 10px;
                margin-bottom: 20px;
            }}
            .toc ul {{
                list-style-type: none;
                padding-left: 20px;
            }}
            .toc li {{
                margin-bottom: 5px;
            }}
            .toc a {{
                text-decoration: none;
                color: #333;
            }}
            .toc a:hover {{
                text-decoration: underline;
            }}
   h1 {{
    color:   #ffffff;
    background-color:  #AC083F   ;
    padding: 5px 20px;
    border-radius: 5px;
    text-align: center;
    font-family: 'Roboto Mono', monospace;
    font-weight: 500 ;

    }}
h2  {{
    display: inline;
    padding: 5px 30px 10px 30px;
    background-color: #1826e9;
    color: #ffffff;
    border-radius: 5px;
    font-weight:400;
}}

li > ul > li > ul > li * {{
opacity: 0.57;
}}

        </style>
        </style>
    </head>
    <body>{content}</body>
    </html>
'''
