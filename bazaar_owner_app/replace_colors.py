import os
import traceback

dir_path = 'c:/Users/IT/.gemini/antigravity/scratch/bazaar_owner_app/lib'

replacements = {
    'const Color(0xFF667eea)': 'AppColors.primary',
    'Color(0xFF667eea)': 'AppColors.primary',
    'const Color(0xFF764ba2)': 'AppColors.secondary',
    'Color(0xFF764ba2)': 'AppColors.secondary',
    'const Color(0xFF302b63)': 'AppColors.primaryDark',
    'Color(0xFF302b63)': 'AppColors.primaryDark',
    'const Color(0xFF0f0c29)': 'AppColors.primary',
    'Color(0xFF0f0c29)': 'AppColors.primary',
    'const Color(0xFF24243e)': 'AppColors.pharaohBlue',
    'Color(0xFF24243e)': 'AppColors.pharaohBlue',
    'const Color(0xFF1A1A2E)': 'AppColors.pharaohBlue',
    'Color(0xFF1A1A2E)': 'AppColors.pharaohBlue',
    'const Color(0xFF0F3460)': 'AppColors.secondary',
    'Color(0xFF0F3460)': 'AppColors.secondary',
    'const Color(0xFF2D3436)': 'AppColors.textPrimary',
    'Color(0xFF2D3436)': 'AppColors.textPrimary',
    'const Color(0xFF636E72)': 'AppColors.textSecondary',
    'Color(0xFF636E72)': 'AppColors.textSecondary',
    'const Color(0xFF10B981)': 'AppColors.success',
    'Color(0xFF10B981)': 'AppColors.success',
    'const Color(0xFFF8F9FA)': 'AppColors.background',
    'Color(0xFFF8F9FA)': 'AppColors.background',
    'const Color(0xFF2D2D2D)': 'AppColors.textPrimary',
    'Color(0xFF2D2D2D)': 'AppColors.textPrimary',
    'const Color(0xFFD4A574)': 'AppColors.primary',
    'Color(0xFFD4A574)': 'AppColors.primary',
    'const Color(0xFF1A5F52)': 'AppColors.secondary',
    'Color(0xFF1A5F52)': 'AppColors.secondary',
    'const Color(0xFF2D8B7A)': 'AppColors.secondaryLight',
    'Color(0xFF2D8B7A)': 'AppColors.secondaryLight',
    # Adding a few more from the grep search
    'const Color(0xFF0D3D34)': 'AppColors.secondaryDark',
    'Color(0xFF0D3D34)': 'AppColors.secondaryDark',
}

files_changed = 0

with open('replace_log.txt', 'w') as log:
    try:
        for root, _, files in os.walk(dir_path):
            if 'colors.dart' in root: continue
            
            for f in files:
                if f.endswith('.dart') and f != 'colors.dart':
                    filepath = os.path.join(root, f)
                    with open(filepath, 'r', encoding='utf-8') as file:
                        content = file.read()

                    new_content = content
                    for old, new in replacements.items():
                        new_content = new_content.replace(old, new)
                    
                    if new_content != content:
                        # Fix up any injected 'const AppColors' errors:
                        for attr in ['primary', 'secondary', 'success', 'background', 'textPrimary', 'textSecondary', 'pharaohBlue', 'primaryDark', 'secondaryLight', 'secondaryDark']:
                            new_content = new_content.replace(f'const AppColors.{attr}', f'AppColors.{attr}')
                            
                        # Try to inject import if needed
                        if 'import ' not in new_content: continue
                        if 'AppColors' in new_content and 'colors.dart' not in new_content:
                            depth = filepath.replace('c:/Users/IT/.gemini/antigravity/scratch/bazaar_owner_app/lib', '').count('\\') + filepath.replace('c:/Users/IT/.gemini/antigravity/scratch/bazaar_owner_app/lib', '').count('/') - 1
                            prefix = '../' * depth if depth > 0 else './'
                            import_stmt = f"import '{prefix}core/constants/colors.dart';\n"
                            
                            last_import_idx = new_content.rfind('import ')
                            end_of_last_import = new_content.find(';', last_import_idx) + 1
                            if end_of_last_import > 0:
                                new_content = new_content[:end_of_last_import] + '\n' + import_stmt + new_content[end_of_last_import:]

                        with open(filepath, 'w', encoding='utf-8') as file:
                            file.write(new_content)
                        log.write(f'Updated {f}\n')
                        files_changed += 1

        log.write(f'SUCCESS! Colors updated in {files_changed} files.\n')
    except Exception as e:
        log.write(traceback.format_exc())
