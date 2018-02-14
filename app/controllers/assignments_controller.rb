class AssignmentsController < ApplicationController
  include AssignmentHelper
  autocomplete :user, :name
  before_action :authorize

  def action_allowed?
    if %w(edit update list_submissions).include? params[:action]
      assignment = Assignment.find(params[:id])
      ['Super-Administrator', 'Administrator'].include? current_role_name or
      assignment.instructor_id == current_user.try(:id) or
      TaMapping.exists?(ta_id: current_user.try(:id), course_id: assignment.course_id) or
      assignment.course_id && Course.find(assignment.course_id).instructor_id == current_user.try(:id)
    else
      ['Super-Administrator',
       'Administrator',
       'Instructor',
       'Teaching Assistant'].include? current_role_name
    end
  end

  # change access permission from public to private or vice versa
  def toggle_access
    assignment = Assignment.find(params[:id])
    assignment.private = !assignment.private
    assignment.save
    redirect_to list_tree_display_index_path
  end

  def new
    @assignment_form = AssignmentForm.new
    @assignment_form.assignment.instructor ||= current_user
  end

  def create
    @assignment_form = AssignmentForm.new(assignment_form_params)

    if @assignment_form.save
      @assignment_form.create_assignment_node

      redirect_to edit_assignment_path @assignment_form.assignment.id
      undo_link("Assignment \"#{@assignment_form.assignment.name}\" has been created successfully. ")
    else
      render 'new'
    end
  end

  def edit
    @assignment = Assignment.find(params[:id])
    @submissions = @assignment.find_due_dates('submission')
    @reviews = @assignment.find_due_dates('review')


    # give an error message is instructor have not set the time zone.
    if current_user.timezonepref.nil?
      flash.now[:error] = "You have not specified your preferred timezone yet. Please do this before you set up the deadlines."
    end

    @topics = SignUpTopic.where(assignment_id: params[:id])
    @assignment_form = AssignmentForm.create_form_object(params[:id])
    @user = current_user

    @assignment_questionnaires = AssignmentQuestionnaire.where(assignment_id: params[:id])
    @due_date_all = AssignmentDueDate.where(parent_id: params[:id])
    @reviewvarycheck = false
    @due_date_nameurl_notempty = false
    @due_date_nameurl_notempty_checkbox = false
    @metareview_allowed = false
    @metareview_allowed_checkbox = false
    @signup_allowed = false
    @signup_allowed_checkbox = false
    @drop_topic_allowed = false
    @drop_topic_allowed_checkbox = false
    @team_formation_allowed = false
    @team_formation_allowed_checkbox = false
    @participants_count = @assignment_form.assignment.participants.size
    @teams_count = @assignment_form.assignment.teams.size

    if @assignment_form.assignment.staggered_deadline == true
      @review_rounds = @assignment_form.assignment.num_review_rounds
      @assignment_submission_due_dates = @due_date_all.select {|due_date| due_date.deadline_type_id == 1 }
      @assignment_review_due_dates = @due_date_all.select {|due_date| due_date.deadline_type_id == 2 }
    end

    # Check if name and url in database is empty before webpage displays
    @due_date_all.each do |dd|
      @due_date_nameurl_notempty = is_due_date_nameurl_notempty(dd)
      @due_date_nameurl_notempty_checkbox = @due_date_nameurl_notempty
      @metareview_allowed = is_meta_review_allowed?(dd)
      @drop_topic_allowed = is_drop_topic_allowed?(dd)
      @signup_allowed = is_signup_allowed?(dd)
      @team_formation_allowed = is_team_formation_allowed?(dd)

      if dd.due_at.present?
        dd.due_at = dd.due_at.to_s.in_time_zone(current_user.timezonepref)
      end
      if  @due_date_nameurl_notempty && @due_date_nameurl_notempty_checkbox &&
          (@metareview_allowed || @drop_topic_allowed || @signup_allowed || @team_formation_allowed)
        break
      end
    end

    @assignment_questionnaires.each do |aq|
      unless aq.used_in_round.nil?
        @reviewvarycheck = 1
        break
      end
    end
    @due_date_all = update_nil_dd_deadline_name(@due_date_all)
    @due_date_all = update_nil_dd_description_url(@due_date_all)

    # only when instructor does not assign rubrics and in assignment edit page will show this error message.
    if !empty_rubrics_list.empty? && request.original_fullpath == "/assignments/#{@assignment_form.assignment.id}/edit"
      rubrics_needed = needed_rubrics(empty_rubrics_list)
      flash.now[:error] = "You did not specify all the necessary rubrics. You need " + rubrics_needed +
          " of assignment <b>#{@assignment_form.assignment.name}</b> before saving the assignment. You can assign rubrics <a id='go_to_tabs2' style='color: blue;'>here</a>."
    end

    if @assignment_form.assignment.directory_path.nil? || @assignment_form.assignment.directory_path.empty?
      flash.now[:error] = "You did not specify your submission directory."
    end
  end

  def update
    unless params.key?(:assignment_form)
      @assignment = Assignment.find(params[:id])
      @assignment.course_id = params[:course_id]
      if @assignment.save
        flash[:note] = 'The assignment was successfully saved.'
        redirect_to list_tree_display_index_path
      else
        flash[:error] = "Failed to save the assignment: #{@assignment.errors.full_messages.join(' ')}"
        redirect_to edit_assignment_path @assignment.id
      end
      return
    end

    @assignment_form = AssignmentForm.create_form_object(params[:id])
    @assignment_form.assignment.instructor ||= current_user

    
    @assignment = Assignment.find(params[:id])
    @submissions = @assignment.find_due_dates('submission')

    params[:assignment_form][:assignment_questionnaire].reject! do |q|
      q[:questionnaire_id].empty?
    end

    # Deleting Due date info from table if meta-review is unchecked. - UNITY ID: ralwan and vsreeni

    @due_date_info = DueDate.find_each(parent_id: params[:id])
    
    if params[:metareviewAllowed] == "false"
      DueDate.where(parent_id: params[:id], deadline_type_id: 5).destroy_all
    end

    if current_user.timezonepref.nil?
      parent_id = current_user.parent_id
      parent_timezone = User.find(parent_id).timezonepref
      flash[:error] = "We strongly suggest that instructors specify their preferred timezone to guarantee the correct display time. For now we assume you are in " + parent_timezone
      current_user.timezonepref = parent_timezone
    end
    
    if params[:set_pressed][:bool] == 'false'
      flash[:error] = "Submissions count greater than rounds of reviews. Please set the value before saving."
    else
      if @assignment_form.update_attributes(assignment_form_params, current_user)
        flash[:note] = 'The assignment was successfully saved....'
      else
        flash[:error] = "Failed to save the assignment: #{@assignment_form.errors.get(:message)}"
      end
    end
    redirect_to edit_assignment_path @assignment_form.assignment.id
  end

  def show
    @assignment = Assignment.find(params[:id])
  end

  def path
    begin
      file_path = @assignment.path
    rescue
      file_path = nil
    end
    file_path
  end

  def copy
    @user = current_user
    session[:copy_flag] = true
    # check new assignment submission directory and old assignment submission directory
    old_assign = Assignment.find(params[:id])
    new_assign_id = AssignmentForm.copy(params[:id], @user)
    if new_assign_id
      new_assign = Assignment.find(new_assign_id)
      if old_assign.directory_path == new_assign.directory_path
        flash[:note] = "Warning: The submission directory for the copy of this assignment will be the same as the submission directory "\
          "for the existing assignment. This will allow student submissions to one assignment to overwrite submissions to the other assignment. "\
          "If you do not want this to happen, change the submission directory in the new copy of the assignment."
      end
      redirect_to edit_assignment_path new_assign_id
    else
      flash[:error] = 'The assignment was not able to be copied. Please check the original assignment for missing information.'
      redirect_to list_tree_display_index_path
    end
  end

  def delete
    begin
      @assignment_form = AssignmentForm.create_form_object(params[:id])
      @user = session[:user]
      id = @user.get_instructor
      if id != @assignment_form.assignment.instructor_id
        raise "You are not authorized to delete this assignment."
      else
        @assignment_form.delete(params[:force])
        flash[:success] = "The assignment was successfully deleted."
      end
    rescue => e
      flash[:error] = e.message
    end
    redirect_to list_tree_display_index_path
  end

  def index
    set_up_display_options("ASSIGNMENT")
    @assignments = super(Assignment)
    # @assignment_pages, @assignments = paginate :assignments, :per_page => 10
  end

  def delayed_mailer
    @suggestions = Suggestion.where(assignment_id: params[:id])
    @assignment = Assignment.find(params[:id])
  end

  def associate_assignment_with_course
    @assignment = Assignment.find(params[:id])
    @courses = Assignment.set_courses_to_assignment(current_user)
  end

  def list_submissions
    @assignment = Assignment.find(params[:id])
    @teams = Team.where(parent_id: params[:id])
  end

  def remove_assignment_from_course
    assignment = Assignment.find(params[:id])
    Assignment.remove_assignment_from_course(assignment)
    redirect_to list_tree_display_index_path
  end

  def delete_delayed_mailer
    @delayed_job = DelayedJob.find(params[:delayed_job_id])
    @delayed_job.delete
    redirect_to delayed_mailer_assignments_index_path params[:id]
  end

  # check whether rubrics are set before save assignment
  def empty_rubrics_list
    rubrics_list = %w(ReviewQuestionnaire
                      MetareviewQuestionnaire AuthorFeedbackQuestionnaire
                      TeammateReviewQuestionnaire BookmarkRatingQuestionnaire)
    @assignment_questionnaires.each do |aq|
      next if aq.questionnaire_id.nil?
      rubrics_list.reject! do |rubric|
        rubric == Questionnaire.where(id: aq.questionnaire_id).first.type.to_s
      end
    end
    if @assignment_form.assignment.max_team_size == 1
      rubrics_list.delete("TeammateReviewQuestionnaire")
    end
    rubrics_list.delete("MetareviewQuestionnaire") unless @metareview_allowed
    unless @assignment_form.assignment.use_bookmark
      rubrics_list.delete("BookmarkRatingQuestionnaire")
    end
    rubrics_list
  end

  def needed_rubrics(empty_rubrics_list)
    needed_rub = "<b>["
    empty_rubrics_list.each do |item|
      needed_rub += item[0...-13] + ", "
    end
    needed_rub = needed_rub[0...-2]
    needed_rub += "] </b>"
    needed_rub
  end

  def is_due_date_nameurl_notempty(dd)
    (!dd.deadline_name.nil? && !dd.deadline_name.empty?) || (!dd.description_url.nil? && !dd.description_url.empty?)
  end

  def is_meta_review_allowed?(dd)
    dd.deadline_type_id == DeadlineHelper::DEADLINE_TYPE_METAREVIEW
  end

  def is_drop_topic_allowed?(dd)
    dd.deadline_type_id == DeadlineHelper::DEADLINE_TYPE_DROP_TOPIC
  end

  def is_signup_allowed?(dd)
    dd.deadline_type_id == DeadlineHelper::DEADLINE_TYPE_SIGN_UP
  end

  def is_team_formation_allowed?(dd)
    dd.deadline_type_id == DeadlineHelper::DEADLINE_TYPE_TEAM_FORMATION
  end

  def update_nil_dd_deadline_name(due_date_all)
    due_date_all.each do |dd|
      dd.deadline_name ||= ''
    end
    due_date_all
  end

  def update_nil_dd_description_url(due_date_all)
    due_date_all.each do |dd|
      dd.description_url ||= ''
    end
    due_date_all
  end

  private

  def assignment_form_params
    params.require(:assignment_form).permit!
  end
end
