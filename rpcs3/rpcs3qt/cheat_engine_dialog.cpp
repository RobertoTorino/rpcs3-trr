#include "stdafx.h"

#include "cheat_engine_dialog.h"

#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QVBoxLayout>

cheat_engine_dialog::cheat_engine_dialog(const QString& path, QWidget* parent)
	: QDialog(parent)
{
	setWindowTitle(tr("Cheat Engine Configuration"));
	setWindowModality(Qt::WindowModal);

	auto* description = new QLabel(tr("Set the path to the Cheat Engine executable."));
	description->setWordWrap(true);

	auto* link = new QLabel(tr("<a href=\"https://github.com/RobertoTorino/cheat-engine-7.2\">CheatEngine 7.2 portable project page</a>"));
	link->setTextFormat(Qt::RichText);
	link->setTextInteractionFlags(Qt::TextBrowserInteraction);
	link->setOpenExternalLinks(true);

	m_path_input = new QLineEdit(path);
	m_path_input->setClearButtonEnabled(true);
	connect(m_path_input, &QLineEdit::textChanged, this, &cheat_engine_dialog::UpdateSaveState);

	auto* browse_button = new QPushButton(tr("Browse..."));
	connect(browse_button, &QPushButton::clicked, this, &cheat_engine_dialog::BrowseForCheatEngine);

	auto* path_row = new QHBoxLayout();
	path_row->addWidget(m_path_input);
	path_row->addWidget(browse_button);

	auto* form = new QFormLayout();
	form->addRow(tr("Executable"), path_row);

	auto* buttons = new QDialogButtonBox(QDialogButtonBox::Save | QDialogButtonBox::Cancel);
	buttons->button(QDialogButtonBox::Save)->setText(tr("Save"));
	m_save_button = buttons->button(QDialogButtonBox::Save);
	connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
	connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

	auto* layout = new QVBoxLayout();
	layout->addWidget(description);
	layout->addWidget(link);
	layout->addLayout(form);
	layout->addWidget(buttons);
	setLayout(layout);

	UpdateSaveState();
}

QString cheat_engine_dialog::get_path() const
{
	return m_path_input->text().trimmed();
}

void cheat_engine_dialog::accept()
{
	const QString path = get_path();
	if (path.isEmpty())
	{
		QMessageBox::warning(this, tr("Warning!"), tr("Please choose a Cheat Engine executable path."));
		return;
	}

	const QFileInfo file_info(path);
	if (!file_info.exists() || !file_info.isFile())
	{
		QMessageBox::warning(this, tr("Warning!"), tr("The selected Cheat Engine executable does not exist."));
		return;
	}

	QDialog::accept();
}

void cheat_engine_dialog::BrowseForCheatEngine()
{
	const QFileInfo current_path(get_path());
	const QString start_dir = current_path.exists() ? current_path.absolutePath() : QString();
	const QString file_path = QFileDialog::getOpenFileName(this, tr("Select Cheat Engine executable"), start_dir,
		tr("Executable files (*.exe);;All files (*.*)"));

	if (!file_path.isEmpty())
	{
		m_path_input->setText(QDir::toNativeSeparators(file_path));
	}
}

void cheat_engine_dialog::UpdateSaveState()
{
	if (m_save_button)
	{
		m_save_button->setEnabled(!get_path().isEmpty());
	}
}