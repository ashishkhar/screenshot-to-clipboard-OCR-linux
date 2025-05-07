# Terminal Screenshot OCR for Linux

A bash script that enables easy OCR (Optical Character Recognition) for terminal text and code snippets on Linux. Take a screenshot of any terminal/code text and have it automatically processed, optimized, and copied to your clipboard.

## Features

- Specialized for terminal text, command outputs, and code snippets
- Automatic dark/light background detection
- Multiple OCR processing methods for optimal results
- Terminal-specific text correction for common OCR mistakes
- Clipboard integration
- Desktop notifications

## Prerequisites

- `gnome-screenshot` - for capturing screen areas
- `imagemagick` - for image processing (`convert` and `identify` commands)
- `tesseract-ocr` - for OCR functionality
- `xclip` - for clipboard operations
- `bc` - for calculations

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/ashishkhar/screenshot-to-clipboard-OCR-linux.git
   ```

2. Install dependencies (Ubuntu/Debian):
   ```
   sudo apt-get update && sudo apt-get install gnome-screenshot imagemagick tesseract-ocr tesseract-ocr-eng xclip bc
   ```

3. Make the script executable:
   ```
   chmod +x screenshot_to_clipboard.sh
   ```

## Usage

1. Run the script:
   ```
   ./screenshot_to_clipboard.sh
   ```

2. Select the area containing terminal text or code
3. Wait for processing (typically a few seconds)
4. The recognized text will be automatically copied to your clipboard

## Notes

This script is not perfect but provides good OCR results for terminal text and code. It works best with:
- Clear, readable terminal fonts
- Reasonable contrast
- Clean backgrounds

## Learn More

Read the detailed article about this script:
[Automating Text Extraction (OCR) from Screenshots with Tesseract and GNOME Screenshot](https://medium.com/@kharbandaashish01/automating-text-extraction-ocr-from-screenshots-with-tesseract-and-gnome-screenshot-db3bcf73e735)

## Keywords

OCR, Linux, Tesseract, terminal text extraction, screenshot text recognition, GNOME Screenshot, ImageMagick, clipboard, bash script, text processing, code extraction, terminal OCR, optical character recognition, Linux automation, text capture

## License

Feel free to modify and distribute according to your needs. 