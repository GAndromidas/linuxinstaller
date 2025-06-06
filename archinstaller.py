#!/usr/bin/env python3
import sys
import os
import subprocess
from pathlib import Path
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                            QHBoxLayout, QRadioButton, QPushButton, QTextEdit, 
                            QProgressBar, QLabel, QGroupBox, QButtonGroup,
                            QMessageBox)
from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtGui import QFont, QTextCursor, QPalette, QColor

class InstallerThread(QThread):
    output_received = pyqtSignal(str)
    finished = pyqtSignal(int)

    def __init__(self, install_mode):
        super().__init__()
        self.install_mode = install_mode

    def run(self):
        script_dir = Path(__file__).parent
        try:
            process = subprocess.Popen(
                [f"{script_dir}/install.sh"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                env={**os.environ, "INSTALL_MODE": self.install_mode}
            )

            for line in process.stdout:
                self.output_received.emit(line.strip())

            process.wait()
            self.finished.emit(process.returncode)
        except Exception as e:
            self.output_received.emit(f"Error: {str(e)}")
            self.finished.emit(1)

class ArchInstallerGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Arch Linux Installer")
        self.setMinimumSize(800, 600)
        
        # Set dark theme colors
        self.setStyleSheet("""
            QMainWindow {
                background-color: #2b2b2b;
            }
            QWidget {
                background-color: #2b2b2b;
                color: #ffffff;
            }
            QGroupBox {
                border: 1px solid #3d3d3d;
                border-radius: 5px;
                margin-top: 1ex;
                font-weight: bold;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 3px 0 3px;
            }
            QRadioButton {
                color: #ffffff;
            }
            QPushButton {
                background-color: #0d47a1;
                color: white;
                border: none;
                padding: 5px 15px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #1565c0;
            }
            QPushButton:disabled {
                background-color: #424242;
            }
            QTextEdit {
                background-color: #1e1e1e;
                color: #ffffff;
                border: 1px solid #3d3d3d;
                border-radius: 3px;
            }
            QProgressBar {
                border: 1px solid #3d3d3d;
                border-radius: 3px;
                text-align: center;
            }
            QProgressBar::chunk {
                background-color: #0d47a1;
            }
        """)

        # Create central widget and main layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(10)
        main_layout.setContentsMargins(20, 20, 20, 20)

        # ASCII Art
        ascii_art = """
      _             _     ___           _        _ _
     / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | | ___ _ __
    / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|
   / ___ \| | | (__| | | || || | | \__ \ || (_| | | |  __/ |
  /_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|\___|_|
        """
        
        ascii_label = QLabel(ascii_art)
        ascii_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        ascii_label.setStyleSheet("color: #00a8ff; font-family: monospace;")
        main_layout.addWidget(ascii_label)

        # Installation Mode Group
        mode_group = QGroupBox("Installation Mode")
        mode_layout = QVBoxLayout()
        
        self.mode_group = QButtonGroup()
        self.default_radio = QRadioButton("Default (Full setup)")
        self.minimal_radio = QRadioButton("Minimal (Core utilities only)")
        self.default_radio.setChecked(True)
        
        self.mode_group.addButton(self.default_radio)
        self.mode_group.addButton(self.minimal_radio)
        
        mode_layout.addWidget(self.default_radio)
        mode_layout.addWidget(self.minimal_radio)
        mode_group.setLayout(mode_layout)
        main_layout.addWidget(mode_group)

        # Output Area
        output_group = QGroupBox("Installation Progress")
        output_layout = QVBoxLayout()
        
        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setFont(QFont("Consolas", 10))
        output_layout.addWidget(self.output_text)
        
        output_group.setLayout(output_layout)
        main_layout.addWidget(output_group)

        # Progress Bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setTextVisible(False)
        main_layout.addWidget(self.progress_bar)

        # Buttons
        button_layout = QHBoxLayout()
        
        self.start_button = QPushButton("Start Installation")
        self.start_button.clicked.connect(self.start_installation)
        
        self.exit_button = QPushButton("Exit")
        self.exit_button.clicked.connect(self.close)
        
        button_layout.addWidget(self.start_button)
        button_layout.addWidget(self.exit_button)
        main_layout.addLayout(button_layout)

        # Initialize installer thread
        self.installer_thread = None

    def append_output(self, text):
        self.output_text.append(text)
        self.output_text.moveCursor(QTextCursor.MoveOperation.End)

    def start_installation(self):
        # Check if running as root
        if os.geteuid() == 0:
            QMessageBox.critical(self, "Error", "Do not run this script as root. Please run as a regular user with sudo privileges.")
            return

        # Check if pacman is available
        if not os.path.exists("/usr/bin/pacman"):
            QMessageBox.critical(self, "Error", "This script is intended for Arch Linux systems with pacman.")
            return

        self.start_button.setEnabled(False)
        self.progress_bar.setRange(0, 0)  # Indeterminate progress
        
        # Get selected mode
        install_mode = "default" if self.default_radio.isChecked() else "minimal"
        
        # Create and start installer thread
        self.installer_thread = InstallerThread(install_mode)
        self.installer_thread.output_received.connect(self.append_output)
        self.installer_thread.finished.connect(self.installation_finished)
        self.installer_thread.start()

    def installation_finished(self, return_code):
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100)
        self.start_button.setEnabled(True)
        
        if return_code == 0:
            self.append_output("\nInstallation completed successfully!")
            QMessageBox.information(self, "Success", "Installation completed successfully!")
        else:
            self.append_output("\nInstallation failed!")
            QMessageBox.critical(self, "Error", "Installation failed! Check the output for details.")

    def closeEvent(self, event):
        if self.installer_thread and self.installer_thread.isRunning():
            reply = QMessageBox.question(
                self, 'Confirm Exit',
                "Installation is in progress. Are you sure you want to exit?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )
            
            if reply == QMessageBox.StandardButton.Yes:
                self.installer_thread.terminate()
                self.installer_thread.wait()
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()

def main():
    app = QApplication(sys.argv)
    window = ArchInstallerGUI()
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
