import os
from fontTools.ttLib import TTFont

# Define the source and target directories
source_path = 'static'
target_path = 'static_modified'

# Create the target directory if it doesn't exist
if not os.path.exists(target_path):
    os.makedirs(target_path)

# Iterate through all files in the source directory
for file_name in os.listdir(source_path):
    if file_name.lower().endswith('.ttf'):
        source_file_path = os.path.join(source_path, file_name)
        target_file_path = os.path.join(target_path, file_name)

        # Load the TTF file
        font = TTFont(source_file_path)

        # Get the value at Position 4 (Name ID 4)
        name_table = font['name']
        full_font_name = None
        for record in name_table.names:
            if record.nameID == 4:
                full_font_name = record.string.decode(record.getEncoding()) if record.isUnicode() else record.string
                break

        if full_font_name:
            # Set the value at Position 16 and 25
            name_table.setName(full_font_name, 16, 3, 1, 0x409)  # For Typographic Family name
            name_table.setName(full_font_name, 25, 3, 1, 0x409)  # For PostScript CID findfont name

        # Save the modified font
        font.save(target_file_path)

        print(f"Modified {file_name} and saved to {target_file_path}")

